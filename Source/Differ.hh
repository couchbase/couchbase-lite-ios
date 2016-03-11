//
//  Differ.hh
//  Mutant
//
//  Created by Jens Alfke on 2/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#ifndef Differ_hh
#define Differ_hh

#include <vector>
#include <iostream>

namespace couchbase {
    namespace differ {

enum Op : uint8_t {
    uninitialized,
    nop,
    del,
    sub,
    ins,
    mov
};

struct Change {
    Op op;
    size_t oldPos, newPos;

    bool operator== (const Change& c) const {
        return op==c.op && oldPos==c.oldPos && newPos==c.newPos;
    }
};

typedef std::vector<Change> ChangeVector;

std::ostream& operator<< (std::ostream&, const Change&);
std::ostream& operator<< (std::ostream&, const ChangeVector&);


class BaseDiffer {
public:
    virtual ~BaseDiffer();

    /** Returns the edit distance between the two vectors */
    uint32_t distance();

    /** If this is set to true, the changes will include 'mov' operations. */
    void setDetectsMoves(bool d) {_detectsMoves = d;}

    /** Returns a shortest set of changes to transform the old into the new. */
    ChangeVector changes();

    unsigned comparisons {0};

#if DEBUG
    void dump();
#endif

protected:
    BaseDiffer() = default;
    void setup(size_t oldLen, size_t newLen);

    virtual bool itemsEqual(size_t oldPos, size_t newPos) const =0;

private:
    struct cell {
        unsigned distance   :24;
        Op op               : 8;
    };

    BaseDiffer(const BaseDiffer&) = delete;

    cell getCell(size_t x, size_t y);
    cell setCell(size_t x, size_t y, cell);
    cell compute(size_t x, size_t y, unsigned maxDistance = UINT_MAX);
    void addChange(Change);
    bool createMove(Change &src, Change &dst);

    size_t _oldLen, _nuuLen;        // Length of old and new arrays
    size_t _prefixLen;              // Length of (skipped) common prefix of old and new

#define STRIPES 1
    
#if STRIPES
    size_t sizeOfStripe(size_t stripe);
    cell*& getStripe(size_t x, size_t y, size_t &outDist);
    cell* allocStripe(size_t x, size_t y);
    cell** _stripes {NULL};
#else
    cell *_table {NULL};            // 2-dimensional table (width=_nuuLen, height=_oldLen)
#endif

    ChangeVector _changes;          // List of Change objects being generated
    bool _detectsMoves {false};     // true if _changes should use 'mov' op
};


template <typename T>
class Differ : public BaseDiffer {
public:
    Differ(const std::vector<T> &old, const std::vector<T> &nuu)
    :_old(old),
     _nuu(nuu)
    {
        setup(old.size(), nuu.size());
    }

protected:
    virtual bool itemsEqual(size_t oldPos, size_t newPos) const {
        return _old[oldPos] == _nuu[newPos];
    }

private:
    const std::vector<T> &_old, &_nuu;
};

    }
}
#endif /* Differ_hh */
