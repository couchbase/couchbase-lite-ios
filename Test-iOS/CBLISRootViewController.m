//
//  CBLISRootViewController.m
//  CouchbaseLite
//
//  Created by florion on 25/01/2016.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLISRootViewController.h"
#import "AppDelegateCBLIS.h"

@interface CBLISRootViewController () <NSFetchedResultsControllerDelegate>

@property (nonatomic, weak) IBOutlet UITableView *tableView;
@property (nonatomic, weak) IBOutlet UIButton *addButton;
@property (nonatomic, strong) NSFetchedResultsController *frc;
@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) NSManagedObject *game;


@end


@implementation CBLISRootViewController

@synthesize frc, context, tableView = _tableView, addButton, game = _game;

- (void)viewDidLoad {
    [super viewDidLoad];
    AppDelegateCBLIS *appDelegate = (AppDelegateCBLIS *)[UIApplication sharedApplication].delegate;
    
    [appDelegate setupCoreDataStackWithCompletion:^{
        self.context = [appDelegate context];
        
        if (self.game == nil) {
            NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Game"];
            request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO]];
            NSArray *games = [self.context executeFetchRequest:request error:nil];
            self.game = games.firstObject;
        }
        
        [self reloadData];
       
    }];
}

- (void)reloadData {
    if (self.game) {
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Team"];
        request.predicate = [NSPredicate predicateWithFormat:@"game == %@", self.game];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]];
        self.frc = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:self.context sectionNameKeyPath:nil cacheName:nil];
        self.frc.delegate = self;
        
        NSError *error;
        [self.frc performFetch:&error];
        
        if (error) {
            NSLog(@"%@", error);
        }
    }
    else {
        self.frc = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.frc.fetchedObjects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    
    if (nil == cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    }
    
    NSManagedObject *obj = [self.frc objectAtIndexPath:indexPath];
    
    cell.textLabel.text = [obj valueForKey:@"name"];
    cell.detailTextLabel.text = @([[obj valueForKey:@"players"] count]).stringValue;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *team = [self.frc objectAtIndexPath:indexPath];
    
    NSManagedObject *player = [NSEntityDescription insertNewObjectForEntityForName:@"Player" inManagedObjectContext:context];
    [player setValue:[NSString stringWithFormat:@"player%d", arc4random_uniform(1000)] forKey:@"name"];
    [player setValue:team forKey:@"team"];
    [self.context insertObject:player];
    [(AppDelegateCBLIS *)[UIApplication sharedApplication].delegate saveContext];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView reloadData];
}

- (IBAction)pickGame:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"" message:@"Game" preferredStyle:UIAlertControllerStyleActionSheet];
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Game"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO]];
    NSArray *games = [self.context executeFetchRequest:request error:nil];
    
    for (NSManagedObject *obj in games) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:[obj valueForKey:@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.game = obj;
            [self reloadData];
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *action = [UIAlertAction actionWithTitle:@"New team" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSManagedObject *game = [NSEntityDescription insertNewObjectForEntityForName:@"Game" inManagedObjectContext:context];
        [game setValue:@"game" forKey:@"name"];
        [self.context insertObject:game];
        [(AppDelegateCBLIS *)[UIApplication sharedApplication].delegate saveContext];
        self.game = game;
        [self reloadData];
    }];
    
    [alert addAction:action];
    
    if (self.game) {
        NSManagedObject *obj = self.game;
        
        UIAlertAction *action = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Delete: %@", [obj valueForKey:@"name"]] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self.context deleteObject:obj];
            self.game = nil;
            
            [(AppDelegateCBLIS *)[UIApplication sharedApplication].delegate saveContext];
            [self reloadData];
        }];
        
        [alert addAction:action];
    }
    
    action = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
    }];
    
    [alert addAction:action];
    
    
    [self showViewController:alert sender:self];
}

- (IBAction)addTeam:(id)sender {
    NSManagedObject *team = [NSEntityDescription insertNewObjectForEntityForName:@"Team" inManagedObjectContext:context];
    [team setValue:[NSString stringWithFormat:@"team%@", @([[self.game valueForKey:@"teams"] count])] forKey:@"name"];
    [team setValue:[NSDate date] forKey:@"date"];
    [team setValue:self.game forKey:@"game"];
    [self.context insertObject:team];
    
    NSInteger max = 20; //arc4random_uniform(10)+5;
    for (int i = 0 ; i < max ; i++) {
        NSManagedObject *player = [NSEntityDescription insertNewObjectForEntityForName:@"Player" inManagedObjectContext:context];
        [player setValue:[NSString stringWithFormat:@"player%d", arc4random_uniform(1000)] forKey:@"name"];
        [player setValue:team forKey:@"team"];
        [self.context insertObject:player];
    }
    
    [(AppDelegateCBLIS *)[UIApplication sharedApplication].delegate saveContext];
}

@end
