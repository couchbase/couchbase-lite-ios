//
//  Differ.cc
//  Mutant
//
//  Created by Jens Alfke on 2/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#include "Differ.hh"
#include <iostream>
#include <iomanip>
#include <assert.h>


namespace couchbase {
    namespace differ {


BaseDiffer::~BaseDiffer() {
#if STRIPES
    if (_stripes) {
        for (size_t stripe = 0; stripe < _nuuLen + _oldLen - 1; ++stripe)
            delete [] _stripes[stripe];
        delete _stripes;
    }
#else
    delete [] _table;
#endif
}


void BaseDiffer::setup(size_t oldLen, size_t newLen) {
    // As an optimization, we can ignore leading & trailing unchanged items.
    // This can't be done in a constructor because it calls the abstract virtual method itemsEqual.
    size_t minLen = std::min(oldLen, newLen);
    size_t prefixLen;
    for (prefixLen = 0; prefixLen < minLen; prefixLen++) {
        if (!itemsEqual(prefixLen, prefixLen))
            break;
    }

    minLen -= prefixLen;
    size_t suffixLen;
    for (suffixLen = 0; suffixLen < minLen; suffixLen++) {
        if (!itemsEqual(oldLen-1 - suffixLen, newLen-1 - suffixLen))
            break;
    }

    _prefixLen = prefixLen;
    _oldLen = oldLen - prefixLen - suffixLen;
    _nuuLen = newLen - prefixLen - suffixLen;
    if (_oldLen > 0 && _nuuLen > 0) {
#if STRIPES
        _stripes = new cell*[_nuuLen + _oldLen - 1]();
#else
        _table = new cell[_nuuLen * (_oldLen)]();
#endif
    }
}


#if STRIPES
inline size_t BaseDiffer::sizeOfStripe(size_t stripe) {
    size_t size = std::min(stripe+1, (_nuuLen+_oldLen-1)-stripe);
    size = std::min(size, std::min(_nuuLen, _oldLen));
    assert(size > 0);
    return size;
}


inline BaseDiffer::cell*& BaseDiffer::getStripe(size_t x, size_t y, size_t &outDist) {
    // Stripes are diagonals of the table, each increasing x and y (down/right).
    // They're numbered starting at the lower left (0, _oldLen-1) and ending at
    // the upper right (_newLen-1, 0).
    size_t stripe = _oldLen-1 + x - y;
    assert(stripe < _nuuLen + _oldLen - 1);
    // outDist is the index of (x,y) along the stripe, starting at the x or y axis.
    outDist = std::min(x, y);
    assert(outDist <= std::min(_nuuLen,_oldLen));
    return _stripes[stripe];
}


BaseDiffer::cell* BaseDiffer::allocStripe(size_t x, size_t y) {
    size_t stripe = _oldLen-1 + x - y;
    size_t stripeSize = sizeOfStripe(stripe);
    return _stripes[stripe] = new cell[stripeSize]();
}
#endif


inline BaseDiffer::cell BaseDiffer::getCell(size_t x, size_t y) {
#if STRIPES
    size_t dist;
    cell* s = getStripe(x, y, dist);
    return s ? s[dist] : cell{0, uninitialized};
#else
    assert(x < _nuuLen);
    assert(y < _oldLen);
    return _table[_nuuLen*y + x];
#endif
}


inline BaseDiffer::cell BaseDiffer::setCell(size_t x, size_t y, cell c) {
#if STRIPES
    size_t dist;
    cell* s = getStripe(x, y, dist) ?: allocStripe(x, y);
    s[dist] = c;
#else
    assert(x < _nuuLen);
    assert(y < _oldLen);
    _table[_nuuLen*y + x] = c;
#endif
    return c;
}
    
    
// Core of the Wagner-Fischer algorithm: https://en.wikipedia.org/wiki/Wagner–Fischer_algorithm
// Basically this returns the edit distance between the first y items of the old array,
// and the first x items of the new array, as well as the opcode of the last operation.
BaseDiffer::cell BaseDiffer::compute(size_t x, size_t y, unsigned maxDistance) {
    assert (x <= _nuuLen && y <= _oldLen);
    // The top and left edge of the table are predefined:
    if (y == 0)
        return {(uint32_t)x, (x ? ins : nop)};
    else if (x == 0)
        return {(uint32_t)y, del};

    // Check the table for an already-computed answer:
    const cell c = getCell(x-1, y-1);
    if (c.op != uninitialized || c.distance > maxDistance) {
        // This cell's already computed, or else it's partially computed and we can tell its full
        // distance would be too big.
        return c;
    }

    // The minimum possible distance from here is equal to the distance from the diagonal.
    // So check if that exceeds maxDistance:
    unsigned fromDiagonal = abs((int)x - (int)y);
    if (fromDiagonal > maxDistance)
        return {fromDiagonal, uninitialized};

    // Compare the old and new items:
    ++comparisons;
    if (itemsEqual(_prefixLen + y-1, _prefixLen + x-1)) {
        // If the items match, this step is a no-op and we proceed up and left:
        return setCell(x-1, y-1, {compute(x-1, y-1, maxDistance).distance, nop});
    }

    // It's going to be one more step, since old and new don't match. So redo the diagonal test:
    if ((++fromDiagonal) > maxDistance) {
        return setCell(x-1, y-1, {fromDiagonal, uninitialized});
    }

    // Look at the 3 cells above or to the left and find the minimum distance:
    unsigned maxd = maxDistance - 1;
    cell upleft = compute(x-1, y-1, maxd);
    maxd = std::min(maxd, upleft.distance);
    cell left = compute(x-1, y, maxd);
    maxd = std::min(maxd, left.distance-1u);
    cell up = compute(x, y-1, maxd);
    cell result;
    if (upleft.distance < up.distance && upleft.distance < left.distance)
        result = {upleft.distance, sub};
    else if (up.distance < left.distance)
        result = {up.distance, del};
    else
        result = {left.distance, ins};
    ++result.distance;

    // If recursive calls stopped after maxDistance, we don't know the true distance.
    if (c.distance > maxDistance)
        result.op = uninitialized;
    // Return what we know:
    return setCell(x-1, y-1, result);
}


#if DEBUG
void BaseDiffer::dump() {
    std::cout << "[Distance = " << distance() << "; made " << comparisons << " comparisons";
#if STRIPES
    if (_stripes) {
        size_t stripeCount = 0, cellCount = 0;
        if (_stripes) {
            for (size_t stripe = 0; stripe < _nuuLen + _oldLen - 1; ++stripe)
                if (_stripes[stripe]) {
                    ++stripeCount;
                    cellCount += sizeOfStripe(stripe);
                }
        }
        std::cout << "; allocated " << stripeCount << " of " << (_nuuLen + _oldLen - 1) << " stripes, " << cellCount << " of " << (_oldLen*_nuuLen) << " cells (" << (cellCount*100.0/(_oldLen*_nuuLen)) << "%]";
    }
#endif
    std::cout << "\n";
    if (_oldLen >= 200 || _nuuLen >= 200)
        return;

    char opNames[] = "_.-=+^";
    for (size_t y = 0; y < _oldLen; y++) {
        for (size_t x = 0; x < _nuuLen; x++) {
            cell c = getCell(x, y);
            std::cout << opNames[c.op];
            if (c.distance == 0 && c.op == uninitialized)
                std::cout << "  ";
            else
                std::cout << std::setw(2) << c.distance;
            std::cout << " ";
        }
        std::cout << "\n";
    }
}
#endif


uint32_t BaseDiffer::distance() {
    return compute(_nuuLen, _oldLen).distance;
}


ChangeVector BaseDiffer::changes() {
    _changes.clear();
    size_t newPos = _nuuLen, oldPos = _oldLen;
    Change ch = {uninitialized, 0, 0};
    while (newPos > 0 || oldPos > 0) {
        ch.oldPos = _prefixLen + oldPos-1;
        ch.newPos = _prefixLen + newPos-1;
        ch.op = compute(newPos, oldPos).op;
        switch (ch.op) {
            case del:
                ch.newPos++;
                oldPos--;
                break;
            case ins:
                ch.oldPos++;
                newPos--;
                break;
            default:
                newPos--; oldPos--;
                break;
        }
        if (ch.op != nop)
            addChange(ch);
        assert(oldPos <= _oldLen && newPos <= _nuuLen);
    }
    std::reverse(_changes.begin(), _changes.end());
    return _changes;
}


void BaseDiffer::addChange(Change ch) {
    if (_detectsMoves) {
        switch (ch.op) {
            case ins:
            case sub:
                // Check if this item was moved here from a later position:
                for (auto src = _changes.begin(); src != _changes.end(); ++src) {
                    if ((src->op == del || src->op == sub) && itemsEqual(src->oldPos, ch.newPos)) {
                        // Move from src to ch:
                        Change origCh = ch;
                        ch.op = mov;
                        ch.oldPos = src->oldPos;
                        if (src->op == sub)
                            src->op = ins;
                        else
                            _changes.erase(src); // src becomes nop; remove it
                        if (origCh.op == sub) {
                            // If a sub becomes the target of a move, there's also a deletion
                            // (to remove the old item.) Make that explicit:
                            addChange({del, origCh.oldPos, origCh.newPos+1});
                        }
                        break;
                    }
                }
                break;
            case del:
                // Check if this item is being moved to a later position:
                for (auto dst = _changes.begin(); dst != _changes.end(); ++dst) {
                    if ((dst->op == ins || dst->op == sub) && itemsEqual(ch.oldPos, dst->newPos)) {
                        // Move from ch to dst:
                        Change origDst = *dst;
                        dst->op = mov;
                        dst->oldPos = ch.oldPos;
                        if (origDst.op == sub) {
                            // If a sub becomes the target of a move, there's also a deletion
                            // (to remove the old item.) Make that explicit:
                            addChange({del, origDst.oldPos, origDst.newPos});
                        }
                        return; // Nothing to add here
                    }
                }
                break;
            default:
                break;
        }
    }
    _changes.push_back(ch);
}


std::ostream& operator<< (std::ostream& out, const Change& ch) {
    static const char* kOpNames[] = {"?", "nop", "del", "sub", "ins", "mov"};
    out << "{" << kOpNames[ch.op] << ", " << ch.oldPos << ", " << ch.newPos << "}";
    return out;
}

std::ostream& operator<< (std::ostream &out, const ChangeVector &ops) {
    out << "{ ";
    for (auto i = ops.begin(); i != ops.end(); ++i) {
        if (i != ops.begin())
            out << ", ";
        out << *i;
    }
    out << " }";
    return out;
}


    }
}
