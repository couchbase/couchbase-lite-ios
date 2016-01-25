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


@end

@implementation CBLISRootViewController

@synthesize frc, context, tableView, addButton;

- (void)viewDidLoad {
    [super viewDidLoad];
    AppDelegateCBLIS *appDelegate = (AppDelegateCBLIS *)[UIApplication sharedApplication].delegate;
    
    [appDelegate setupCoreDataStackWithCompletion:^{
        self.context = [appDelegate context];
        
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Team"];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]];
        self.frc = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:self.context sectionNameKeyPath:nil cacheName:nil];
        self.frc.delegate = self;
        
        NSError *error;
        [self.frc performFetch:&error];
        
        if (error) {
            NSLog(@"%@", error);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
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

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView reloadData];
}

- (IBAction)addTeam:(id)sender {
    NSManagedObject *team = [NSEntityDescription insertNewObjectForEntityForName:@"Team" inManagedObjectContext:context];
    [team setValue:[NSString stringWithFormat:@"team%d", arc4random_uniform(1000)] forKey:@"name"];
    [team setValue:[NSDate date] forKey:@"date"];
    [self.context insertObject:team];
    
    NSInteger max = arc4random_uniform(10);
    for (int i = 0 ; i < max ; i++) {
        NSManagedObject *player = [NSEntityDescription insertNewObjectForEntityForName:@"Player" inManagedObjectContext:context];
        [player setValue:[NSString stringWithFormat:@"player%d", arc4random_uniform(1000)] forKey:@"name"];
        [player setValue:team forKey:@"team"];
        [self.context insertObject:player];
    }
    
    [(AppDelegateCBLIS *)[UIApplication sharedApplication].delegate saveContext];
}

@end
