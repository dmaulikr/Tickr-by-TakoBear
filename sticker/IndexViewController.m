//
//  ViewController.m
//  sticker
//
//  Created by 李健銘 on 2014/2/18.
//  Copyright (c) 2014年 TakoBear. All rights reserved.
//

#import "IndexViewController.h"
#import "PhotoViewCell.h"
#import "DraggableCollectionViewFlowLayout.h"
#import "UICollectionView+Draggable.h"
#import "UICollectionViewDataSource_Draggable.h"
#import "FileControl.h"
#import "SettingViewController.h"
#import "ChatManager.h"
#import "SettingVariable.h"
#import "JMDropMenuView.h"
#import "PhotoEditedViewController.h"
#import "GoogleSearchViewController.h"
#import <QuartzCore/QuartzCore.h>
// For popout setting menus
#import "External/REMenu/REMenu.h"
#import "External/RATreeView/RADataObject.h"
#import "External/RATreeView/RATreeView.h"
// For popout IM menus
#import "External/WYPopoverController/WYPopoverController.h"
#import "IMSelectViewController.h"
#import "UIImage+ResizeImage.h"

#define kBLOCKVIEW_TAG           1001
#define kDEFAULT_VIEW_CELL_TAG   1002
#define kSAVE_ALBUM_CELL_TAG     1003
#define kADD_NEW_PHOTO_TAG       1004

typedef NS_ENUM(NSInteger, kAdd_Photo_From) {
    kAdd_Photo_From_Camera,
    kAdd_Photo_From_Album,
    kAdd_Photo_From_Search
};

@interface IndexViewController ()<UICollectionViewDataSource_Draggable, UICollectionViewDataSource,UICollectionViewDelegate,JMDropMenuViewDelegate,UINavigationControllerDelegate,UIImagePickerControllerDelegate, RATreeViewDataSource, RATreeViewDelegate, WYPopoverControllerDelegate>
{
    DraggableCollectionViewFlowLayout *flowLayout;
    WYPopoverController *defaultIMPopOverViewController;
    JMDropMenuView *dropMenu;
    REMenu *settingMenu;
    UICollectionView *imageCollectionView;
    NSMutableArray *imageDataArray;
    NSMutableArray *imageURLArray;
    NSArray *optionData;
    NSString *documentPath;
    NSString *lastImageURL;
    UIImagePickerController *imagePicker;
    BOOL isAddMode;
    BOOL isSettingOpen;
    BOOL isAnimate;
    BOOL isDeleteMode;
    CABasicAnimation *shakeAnimate;
}

@end

@implementation IndexViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    imageDataArray = [NSMutableArray new];
    imageURLArray = [NSMutableArray new];
    isAddMode = NO;
    isAnimate = NO;
    isDeleteMode = NO;
    
    self.navigationItem.title = NSLocalizedString(@"Tickr", @"");
    
    //Create Shake Animate
    shakeAnimate = [[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"] retain];
    shakeAnimate.fromValue = [NSNumber numberWithFloat:-0.03];
    shakeAnimate.toValue = [NSNumber numberWithFloat:+0.03];
    shakeAnimate.duration = 0.1;
    shakeAnimate.autoreverses = YES;
    shakeAnimate.repeatCount = FLT_MAX;
    
    // Configure Setting icon
    // Customise TreeView
    RADataObject *appLINE = [RADataObject dataObjectWithName:@"LINE" children:nil];
    RADataObject *appWhatsApp = [RADataObject dataObjectWithName:@"WhatsApp" children:nil];
    RADataObject *appWeChat = [RADataObject dataObjectWithName:@"WeChat" children:nil];
    RADataObject *defaultIM = [RADataObject dataObjectWithName:NSLocalizedString(@"Default IM", nil) children:@[appLINE, appWhatsApp, appWeChat]];
    
    RADataObject *destinationObj = [RADataObject dataObjectWithName:NSLocalizedString(@"Save to Group Album", @"") children:nil];
    RADataObject *takobearDestWeb = [RADataObject dataObjectWithName:NSLocalizedString(@"Go to TakoBear", @"") children:nil];
    
    RATreeView *treeView = [[RATreeView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:RATreeViewStylePlain];
    [treeView setBackgroundColor:[UIColor clearColor]];
    [treeView setSeparatorColor:[UIColor clearColor]];
    treeView.delegate = self;
    treeView.dataSource = self;
    
    // Compose the MenuItem
    REMenuItem *settingItem = [[REMenuItem alloc] initWithCustomView:treeView];
    optionData = @[defaultIM, destinationObj, takobearDestWeb]; [optionData retain];
    [treeView reloadData];
    
    BOOL isOn = [[NSUserDefaults standardUserDefaults] boolForKey:kIMDefaultKey];
    if (isOn) {
        [treeView expandRowForItem:optionData[0] withRowAnimation:RATreeViewRowAnimationBottom];
    }
    
    settingMenu = [[REMenu alloc] initWithItems:@[settingItem]];
    [settingMenu.backgroundView setBackgroundColor:[UIColor clearColor]];
    [settingMenu setBorderColor:[UIColor clearColor]];
    [settingMenu setBackgroundColor:[UIColor clearColor]];
    settingMenu.itemHeight = self.view.frame.size.height;
    
    isSettingOpen = NO;
    
    //Create navigation bar & items
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"add_photo.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(displayAddMenu:)];
    UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(changeDeleteMode:)];
    UIBarButtonItem *settingButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"dropmenu_pressed.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(pushToSettingView:)];
    settingButton.tintColor = [UIColor whiteColor];

    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:addButton,deleteButton, nil];
    self.navigationItem.leftBarButtonItem = settingButton;
    
    //Create a StickerDocument folder in path : var/.../Document/
    NSArray *docDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    documentPath = [[docDirectory objectAtIndex:0] retain];
    NSString *stickerPath = [documentPath stringByAppendingPathComponent:kFileStoreDirectory];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    if (![fileManager fileExistsAtPath:stickerPath]) {
        [fileManager createDirectoryAtPath:stickerPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:&error];
    }
    
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    if ([userDefault objectForKey:KTakoBearKey] == nil) {
        UIImage *takoBear = [UIImage imageNamed:@"takobear_logo.png"];
        NSString *stickerPath = [[[FileControl mainPath] documentPath] stringByAppendingPathComponent:kFileStoreDirectory];
        NSData *imageData = UIImagePNGRepresentation(takoBear);
        BOOL isWrite = [imageData writeToFile:[stickerPath stringByAppendingPathComponent:@"takobear.jpg"] atomically:YES];
        [userDefault setObject:[NSNumber numberWithBool:isWrite] forKey:KTakoBearKey];
    }
    
    
    //Get only "image name" from  path : var/.../Document/StickerDocument/* and sort ascending by name
    NSArray *fileArray = [[NSArray arrayWithArray:[fileManager contentsOfDirectoryAtPath:stickerPath error:&error]] retain];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:nil ascending:NO selector:@selector(compare:)];
    fileArray = [fileArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
    if (fileArray.count > 0 ) {
        lastImageURL = [[fileArray objectAtIndex:0]retain];
    }
    imageDataArray = [[NSMutableArray arrayWithArray:fileArray] retain];
    imageURLArray = [[NSMutableArray arrayWithArray:fileArray] retain];
    SettingVariable *settingVariable = [SettingVariable sharedInstance];
    [settingVariable.variableDictionary setObject:imageDataArray forKey:kImageDataArrayKey];
    
    
    //Create CollectionView
    flowLayout = [[DraggableCollectionViewFlowLayout alloc] init];
    [flowLayout setItemSize:CGSizeMake(100,100)];
    [flowLayout setScrollDirection:UICollectionViewScrollDirectionVertical];
    
    imageCollectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 10, self.view.frame.size.width, self.view.frame.size.height) collectionViewLayout:flowLayout];
    [imageCollectionView setDelegate:self];
    [imageCollectionView setDataSource:self];
    [imageCollectionView setDraggable:YES];
    [imageCollectionView setBackgroundColor:[UIColor clearColor]];
    [imageCollectionView registerClass:[PhotoViewCell class] forCellWithReuseIdentifier:@"collectionCell"];
    
    [self.view addSubview:imageCollectionView];
    
    //Create drop menu
    UIImageView *cameraDrop = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kAddMenuIconSize, kAddMenuIconSize)];
    cameraDrop.backgroundColor = [UIColor clearColor];
    [cameraDrop setImage:[UIImage imageNamed:@"camera.png"]];
    [self.view addSubview:cameraDrop];
    
    UIImageView *albumDrop = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kAddMenuIconSize, kAddMenuIconSize)];
    albumDrop.backgroundColor = [UIColor clearColor];
    [albumDrop setImage:[UIImage imageNamed:@"album.png"]];
    [self.view addSubview:albumDrop];
    
    UIImageView *searchDrop = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kAddMenuIconSize, kAddMenuIconSize)];
    searchDrop.backgroundColor = [UIColor clearColor];
    [searchDrop setImage:[UIImage imageNamed:@"search.png"]];
    [self.view addSubview:searchDrop];
    
    if ([userDefault objectForKey:KAddNewPhotoKey] == nil) {
        UIImage *addNewPhoto = [UIImage imageNamed:@"AddNewPhoto.png"];
        UIImageView *addNewView = [[UIImageView alloc] init];
        if ([[UIScreen mainScreen] bounds].size.height == 480.0f) {
            addNewView.frame = CGRectMake(0, 34, self.view.frame.size.width, self.view.frame.size.height+40);
        } else {
            addNewView.frame = CGRectMake(0, 54, self.view.frame.size.width, self.view.frame.size.height-44);
        }
        addNewView.contentMode = UIViewContentModeScaleAspectFit;
        addNewView.image = addNewPhoto;
        addNewView.tag = kADD_NEW_PHOTO_TAG;
        [self.view addSubview:addNewView];
        [addNewView release];
    }
    
    dropMenu= [[JMDropMenuView alloc] initWithViews:@[cameraDrop, albumDrop, searchDrop]];
    dropMenu.frame = CGRectMake(self.view.bounds.size.width - kAddMenuIconSize, 70, kAddMenuIconSize, kAddMenuIconSize *3);
    dropMenu.animateInterval = 0.15;
    dropMenu.delegate = self;
    dropMenu.userInteractionEnabled = NO;
    [self.view addSubview:dropMenu];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    self.navigationController.navigationBarHidden = NO;
    self.navigationController.toolbarHidden = YES;
    if (imageDataArray.count == 0) {
        return;
    }
    
    id newLastImageURL = [imageDataArray objectAtIndex:0];
    if ([newLastImageURL isKindOfClass:[UIImage class]]) {
        return;
    }
    if (![newLastImageURL isEqualToString:lastImageURL]) {
        [imageURLArray insertObject:newLastImageURL atIndex:0];
        lastImageURL = newLastImageURL;
        [imageCollectionView reloadData];
    }
}

- (void)dealloc
{
    [flowLayout release];
    [imageCollectionView release];
    [imageDataArray release];
    [imageURLArray release];
    [lastImageURL release];
    [documentPath release];
    [dropMenu release];
    [settingMenu release];
    [shakeAnimate release];
//    [cellQueue release];
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)pushToSettingView:(id)sender
{
    UIBarButtonItem *btn = (UIBarButtonItem *)sender;
    if (settingMenu.isAnimating) {
        return;
    }
    
    if (isSettingOpen) {
        btn.tintColor = [UIColor whiteColor];
        [settingMenu close];
        for (UIBarButtonItem *btn in self.navigationItem.rightBarButtonItems) {
            btn.enabled = YES;
        }
        imageCollectionView.userInteractionEnabled = YES;
    } else {
        [self cancelAddModeWithOtherButton];
        [self cancelDeleteModeWithOtherButton];
        
        btn.tintColor = DARK_ORAGE_COLOR;
        if (isAddMode) {
            [dropMenu dismiss];
            isAddMode = NO;
        }
        for (UIBarButtonItem *btn in self.navigationItem.rightBarButtonItems) {
            btn.enabled = NO;
        }
        imageCollectionView.userInteractionEnabled = NO;
        [settingMenu showFromNavigationController:self.navigationController];
    }
    
    isSettingOpen = !isSettingOpen;
}

#pragma mark - Delete mode

- (void)cancelDeleteModeWithOtherButton
{
    if (isDeleteMode) {
        UIBarButtonItem *btn = [self.navigationItem.rightBarButtonItems objectAtIndex:1];
        btn.tintColor = [UIColor whiteColor];
        isDeleteMode = NO;
        [imageCollectionView reloadData];
    }

}

- (void)changeDeleteMode:(id)sender
{
    isDeleteMode = !isDeleteMode;
    UIBarButtonItem *btn = (UIBarButtonItem *)sender;
    if (isDeleteMode) {
        btn.tintColor = DARK_ORAGE_COLOR;
        [self cancelAddModeWithOtherButton];
    } else {
        btn.tintColor = [UIColor whiteColor];
    }
    [imageCollectionView reloadData];
}

#pragma mark - Drop menu Delegate for add photo

- (void)didFinishedPopOutWithDropMenu:(JMDropMenuView *)menu
{
    dropMenu.userInteractionEnabled = YES;
    isAnimate = NO;
}

- (void)didFinishedDismissWithDropMenu:(JMDropMenuView *)menu
{
    dropMenu.userInteractionEnabled = NO;
    imageCollectionView.userInteractionEnabled = YES;
    isAnimate = NO;
}

- (void)cancelAddModeWithOtherButton
{
    if (isAddMode) {
        UIBarButtonItem *btn = [self.navigationItem.rightBarButtonItems objectAtIndex:0];
        btn.image = [UIImage imageNamed:@"add_photo.png"];
        btn.tintColor = [UIColor whiteColor];
        [dropMenu dismiss];
    }
}

- (void)displayAddMenu:(id)sender
{
    UIBarButtonItem *btn = (UIBarButtonItem *)sender;
    if (isAnimate) {
        return;
    }
    isAnimate = YES;
    dropMenu.userInteractionEnabled = NO;
    if (isAddMode) {
        btn.image = [UIImage imageNamed:@"add_photo.png"];
        btn.tintColor = [UIColor whiteColor];
        [dropMenu dismiss];
    } else {
        [self cancelDeleteModeWithOtherButton];
        btn.image = [UIImage imageNamed:@"add_cancel.png"];
        btn.tintColor = DARK_ORAGE_COLOR;
        imageCollectionView.userInteractionEnabled = NO;
        [dropMenu popOut];
    }
    isAddMode = !isAddMode;
    
    NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
    if ([userDefault objectForKey:KAddNewPhotoKey] == nil) {
        [userDefault setValue:[NSNumber numberWithBool:YES] forKey:KAddNewPhotoKey];
        UIImageView *addNewImgView = (UIImageView *)[self.view viewWithTag:kADD_NEW_PHOTO_TAG];
        [UIView animateWithDuration:0.5 animations:^{
            addNewImgView.alpha = 0;
        }completion:^(BOOL finished){
            if (finished)
            [addNewImgView removeFromSuperview];
        }];
    }

}

- (void)dropMenu:(JMDropMenuView *)menu didSelectAtIndex:(NSInteger)index;
{
    [dropMenu resetPosition];
    dropMenu.userInteractionEnabled = NO;
    isAddMode = NO;
    imageCollectionView.userInteractionEnabled = YES;
    switch (index) {
        case kAdd_Photo_From_Album:{
            [self getLocalPhoto];
        }
            break;
        case kAdd_Photo_From_Camera:{
            [self cameraAction];
        }
            break;
        case kAdd_Photo_From_Search:{
            [self googleSearchAction];
        }
            break;
            
        default:
            break;
    }
    UIBarButtonItem *btn = self.navigationItem.rightBarButtonItems[0];
    btn.image = [UIImage imageNamed:@"add_photo.png"];
    btn.tintColor = [UIColor whiteColor];
}

#pragma mark - CollectionView dataSource & Delegate

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return imageDataArray.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    
    PhotoViewCell *cell = (PhotoViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:@"collectionCell" forIndexPath:indexPath];
    [cell.imgView setContentMode:UIViewContentModeScaleAspectFit];
    UIImage *image;
    NSString *stickerPath = [documentPath stringByAppendingPathComponent:kFileStoreDirectory];
    if ([[imageDataArray objectAtIndex:indexPath.item] isKindOfClass:[NSString class]]) {
        NSString *imagePath = [stickerPath stringByAppendingPathComponent:[imageDataArray objectAtIndex:indexPath.item]];
        NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
        image = [UIImage imageWithData:imageData];
        image = [UIImage resizeImageWithSize:image resize:CGSizeMake(150, 150)];
        [imageDataArray replaceObjectAtIndex:indexPath.item withObject:image];
    } else {
        image = [imageDataArray objectAtIndex:indexPath.item];
    }
    
    if (isDeleteMode) {
        [cell.layer addAnimation:shakeAnimate forKey:@"delete_cell"];
        cell.deleteImgView.hidden = NO;
    } else {
        cell.deleteImgView.hidden = YES;
    }
    
    [cell.imgView setImage:image];
    
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (isDeleteMode) {
        [self deletePhoto:indexPath.item];
        [self cancelDeleteModeWithOtherButton];
    } else {
        [self handleSelectPhoto:indexPath collectionView:collectionView];
    }

}

#pragma mark - Action when touching Photo

- (void)handleSelectPhoto:(NSIndexPath *)indexPath collectionView:(UICollectionView *)collectionView
{
    BOOL isOn = [[NSUserDefaults standardUserDefaults] boolForKey:kIMDefaultKey];
    if (isOn) {
        // Pass photo to IM messenger
        NSString *stickerPath = [documentPath stringByAppendingPathComponent:kFileStoreDirectory];
        NSString *imagePath = [stickerPath stringByAppendingPathComponent:[imageURLArray objectAtIndex:indexPath.item]];
        NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
        ChatManager *chatManager = [ChatManager new];
        ChatApp *chat = [chatManager currentChatAppWithType];
        if ([chat isUserInstalledApp]) {
            [chat shareWithImage:imageData];
        }
    } else {
        // Pop out select IM messenger
        PhotoViewCell *cell = (PhotoViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:@"collectionCell" forIndexPath:indexPath];
        NSString *stickerPath = [documentPath stringByAppendingPathComponent:kFileStoreDirectory];
        NSString *imagePath = [stickerPath stringByAppendingPathComponent:[imageURLArray objectAtIndex:indexPath.item]];
        NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
        [self touchPhoto:cell andData:imageData indexPath:indexPath];
    }
}

- (void)touchPhoto:(PhotoViewCell *)cell andData:(NSData *)imageData indexPath:(NSIndexPath *)indexPath
{
    IMSelectViewController *vc = [[IMSelectViewController alloc] initWithImageData:imageData];
    
    defaultIMPopOverViewController = [[WYPopoverController alloc] initWithContentViewController:vc];
    defaultIMPopOverViewController.delegate = self;
    defaultIMPopOverViewController.passthroughViews = @[cell];
    if ([[UIScreen mainScreen] bounds].size.height == 480.0f) {
        defaultIMPopOverViewController.popoverLayoutMargins = UIEdgeInsetsMake(100, 0, 180, 0);
    } else if ([[UIScreen mainScreen] bounds].size.height == 568.0f) {
        defaultIMPopOverViewController.popoverLayoutMargins = UIEdgeInsetsMake(200, 0, 180, 0);
    }
    defaultIMPopOverViewController.wantsDefaultContentAppearance = NO;
    
    // Get current Cell position
    UICollectionViewLayoutAttributes *attributes = [imageCollectionView layoutAttributesForItemAtIndexPath:indexPath];
    CGRect cellRect = attributes.frame;
    CGRect cellFrameInSuperview = [imageCollectionView convertRect:cellRect toView:[imageCollectionView superview]];
    
    UIView *blockView = [[UIView alloc] initWithFrame:cellFrameInSuperview];
    blockView.backgroundColor = [UIColor clearColor];
    blockView.tag = kBLOCKVIEW_TAG;
    [self.view addSubview:blockView];
    
    [defaultIMPopOverViewController presentPopoverFromRect:blockView.frame
                                                   inView:self.view
                                 permittedArrowDirections:WYPopoverArrowDirectionAny
                                                 animated:YES
                                                  options:WYPopoverAnimationOptionFadeWithScale];
    
}

- (void)popoverControllerDidDismissPopover:(WYPopoverController *)popoverController;
{
    if (defaultIMPopOverViewController) {
        UIView *blockView = [self.view viewWithTag:kBLOCKVIEW_TAG];
        [blockView removeFromSuperview];
        [blockView release], blockView = nil;
        [defaultIMPopOverViewController release];
        defaultIMPopOverViewController = nil;
    }
}


#pragma mark - WYPopoverControllerDelegate

- (void)popoverControllerDidPresentPopover:(WYPopoverController *)controller
{
    NSLog(@"popoverControllerDidPresentPopover");
}

- (BOOL)popoverControllerShouldDismissPopover:(WYPopoverController *)controller
{
    return YES;
}

- (BOOL)popoverControllerShouldIgnoreKeyboardBounds:(WYPopoverController *)popoverController
{
    return YES;
}

- (void)popoverController:(WYPopoverController *)popoverController willTranslatePopoverWithYOffset:(float *)value
{
    // keyboard is shown and the popover will be moved up by 163 pixels for example ( *value = 163 )
    *value = 0; // set value to 0 if you want to avoid the popover to be moved
}

#pragma mark - UIViewControllerRotation

// Applications should use supportedInterfaceOrientations and/or shouldAutorotate..
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

// New Autorotation support.
- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}


#pragma mark - Draggable delegate

- (BOOL)collectionView:(LSCollectionViewHelper *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)toIndexPath
{
    return YES;
}

- (void)collectionView:(LSCollectionViewHelper *)collectionView moveItemAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
    UIImage *index = [imageDataArray objectAtIndex:fromIndexPath.item];
    [imageDataArray removeObjectAtIndex:fromIndexPath.item];
    [imageDataArray insertObject:index atIndex:toIndexPath.item];
    NSString *string = [imageURLArray objectAtIndex:fromIndexPath.item];
    [imageURLArray removeObjectAtIndex:fromIndexPath.item];
    [imageURLArray insertObject:string atIndex:toIndexPath.item];
}

- (void)deletePhoto:(NSInteger)item
{
    
    NSString *stickerPath = [documentPath stringByAppendingPathComponent:kFileStoreDirectory];
    NSString *deletePath = [NSString stringWithFormat:@"%@/%@",stickerPath,imageURLArray[item]];
    [[FileControl mainPath] removeFileAtPath:deletePath];
    [imageDataArray removeObjectAtIndex:item];
    [imageURLArray removeObjectAtIndex:item];

}

#pragma mark - Method to get Image

- (void)cameraAction
{
    imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
    imagePicker.allowsEditing = YES;
    imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
    [self presentViewController:imagePicker animated:YES completion:nil];
}

- (void)getLocalPhoto
{
    imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    [self presentViewController:imagePicker animated:YES completion:nil];
    
}

- (void)googleSearchAction
{
    GoogleSearchViewController *searchVC = [[GoogleSearchViewController alloc] init];
    UINavigationController *navigationController = [[[UINavigationController alloc] initWithRootViewController:searchVC] autorelease];
    
    [self presentViewController:navigationController animated:YES completion:nil];
    [searchVC release];
}

#pragma mark - UIimagePickerController Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *pickImage = [info objectForKey:@"UIImagePickerControllerOriginalImage"];
    [imagePicker dismissViewControllerAnimated:YES completion:nil];
    imagePicker.delegate = nil;
    imagePicker = nil;
    [imagePicker release];
    float ratio = pickImage.size.height/pickImage.size.width;
    pickImage = [UIImage resizeImageWithSize:pickImage resize:CGSizeMake(600 / ratio, 600)];
    [self sendImageToEditViewControllWith:pickImage];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker;
{
    [imagePicker dismissViewControllerAnimated:YES completion:nil];
    imagePicker.delegate = nil;
    imagePicker = nil;
    [imagePicker release];
}

- (void)sendImageToEditViewControllWith:(UIImage *)image
{
    PhotoEditedViewController *editViewController = [[PhotoEditedViewController alloc] init];
    editViewController.sourceImage = image;
    editViewController.previewImage = image;
    //    editViewController.checkBounds = YES;
    [editViewController reset:NO];
    
    [self.navigationController pushViewController:editViewController animated:NO];
    [editViewController release];
}

#pragma mark TreeView Data Source
- (BOOL)treeView:(RATreeView *)treeView canEditRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    return NO;
}

- (UITableViewCell *)treeView:(RATreeView *)treeView cellForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    
    cell.textLabel.text = ((RADataObject *)item).name;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    if (treeNodeInfo.treeDepthLevel == 0) {
        
        cell.textLabel.textColor = [UIColor whiteColor];
        UISwitch *switchBtn = [[[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 60, 40)] autorelease];
        switchBtn.onTintColor = RGBA(247.0f, 166.0f, 0.0f, 1.0f);
        
        switch (treeNodeInfo.positionInSiblings) {
            case 0:
            {
                [switchBtn addTarget:self action:@selector(switchDefaultIMSetting:) forControlEvents:UIControlEventTouchUpInside];
                BOOL isOn = [[NSUserDefaults standardUserDefaults] boolForKey:kIMDefaultKey];
                [switchBtn setOn:isOn];
                cell.tag = kDEFAULT_VIEW_CELL_TAG;
            }
                break;
            case 1:
            {
                [switchBtn addTarget:self action:@selector(switchAlbumSetting:) forControlEvents:UIControlEventTouchUpInside];
                BOOL isOn = [[NSUserDefaults standardUserDefaults] boolForKey:kSaveAlbumKey];
                [switchBtn setOn:isOn];
                cell.tag = kSAVE_ALBUM_CELL_TAG;
            }
                break;
        }
        
        if (treeNodeInfo.positionInSiblings != 2) {
            cell.accessoryView = switchBtn;
        }
        
        NSLog(@"item %d", treeNodeInfo.positionInSiblings);
        
    } else {
        
        int chatType = [[[NSUserDefaults standardUserDefaults] objectForKey:kChooseChatAppTypeKey] intValue];
        int row = treeNodeInfo.positionInSiblings;
        UIImage *selectedImg = [UIImage imageNamed:@"selected.png"];
        UIImageView *selectedImgView = [[[UIImageView alloc] initWithImage:selectedImg] autorelease];
        if ( chatType == row) {
            cell.accessoryView = selectedImgView;
            cell.textLabel.textColor = RGBA(247.0f, 166.0f, 0.0f, 1.0f);
        } else {
            cell.accessoryView = nil;
            cell.textLabel.textColor = [UIColor whiteColor];
        }

    }
    
    return cell;
}

- (NSInteger)treeView:(RATreeView *)treeView numberOfChildrenOfItem:(id)item
{
    if (item == nil) {
        return [optionData count];
    }
    
    RADataObject *_data = item;
    return [_data.children count];
}

- (id)treeView:(RATreeView *)treeView child:(NSInteger)index ofItem:(id)item
{
    RADataObject *_data = item;
    if (item == nil) {
        return [optionData objectAtIndex:index];
    }
    
    return [_data.children objectAtIndex:index];
}

#pragma mark TreeView Delegate methods

- (void)treeView:(RATreeView *)treeView didSelectRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    if (treeNodeInfo.treeDepthLevel == 1) {
        switch (treeNodeInfo.positionInSiblings) {
            case ChatAppType_Line:
            {
                [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithInt:ChatAppType_Line] forKey:kChooseChatAppTypeKey];
                [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:ChatAppType_Line] forKey:kChooseChatAppTypeKey];

            }
                break;
            case ChatAppType_WhatsApp:
            {
                [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithInt:ChatAppType_WhatsApp] forKey:kChooseChatAppTypeKey];
                [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:ChatAppType_WhatsApp] forKey:kChooseChatAppTypeKey];
            }
                break;
            case ChatAppType_WeChat:
            {
                [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithInt:ChatAppType_WeChat] forKey:kChooseChatAppTypeKey];
                [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:ChatAppType_WeChat] forKey:kChooseChatAppTypeKey];
            }
                break;
            default:
                break;
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
        [treeView reloadRows];
        
    } else if (treeNodeInfo.treeDepthLevel == 0 && treeNodeInfo.positionInSiblings == 1) {
        UITableViewCell *cell = (UITableViewCell *)[treeView viewWithTag:kSAVE_ALBUM_CELL_TAG];
        UISwitch *btn = (UISwitch *)cell.accessoryView;
        [btn setOn:!btn.isOn animated:YES];
        [self switchAlbumSetting:btn];
    } else if (treeNodeInfo.treeDepthLevel == 0 && treeNodeInfo.positionInSiblings == 2) {
        // Direct to Takobear websit
        [[UIApplication sharedApplication] openURL:TAKOBEAR_WEBSITE];
    }
    
}

- (CGFloat)treeView:(RATreeView *)treeView heightForRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    return 55;
}

- (NSInteger)treeView:(RATreeView *)treeView indentationLevelForRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    return 3 * treeNodeInfo.treeDepthLevel;
}

- (BOOL)treeView:(RATreeView *)treeView shouldItemBeExpandedAfterDataReload:(id)item treeDepthLevel:(NSInteger)treeDepthLevel
{
    return NO;
}

- (BOOL)treeView:(RATreeView *)treeView shouldExpandRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    if (treeNodeInfo.treeDepthLevel == 0 && treeNodeInfo.positionInSiblings == 0) {
        // Save setting to userinfo
        [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:YES] forKey:kIMDefaultKey];
        UITableViewCell *cell = (UITableViewCell *)[treeView viewWithTag:kDEFAULT_VIEW_CELL_TAG];
        UISwitch *btn = (UISwitch *)cell.accessoryView;
        [btn setOn:YES animated:YES];
        [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:btn.isOn] forKey:kIMDefaultKey];
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:btn.isOn] forKey:kIMDefaultKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    return YES;
}

- (BOOL)treeView:(RATreeView *)treeView shouldCollapaseRowForItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    if (treeNodeInfo.treeDepthLevel == 0 && treeNodeInfo.positionInSiblings == 0) {
        // Save setting to userinfo
        [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:NO] forKey:kIMDefaultKey];
        UITableViewCell *cell = (UITableViewCell *)[treeView viewWithTag:kDEFAULT_VIEW_CELL_TAG];
        UISwitch *btn = (UISwitch *)cell.accessoryView;
        [btn setOn:NO animated:YES];
        [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:btn.isOn] forKey:kIMDefaultKey];
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:btn.isOn] forKey:kIMDefaultKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    return YES;
}

- (void)treeView:(RATreeView *)treeView willDisplayCell:(UITableViewCell *)cell forItem:(id)item treeNodeInfo:(RATreeNodeInfo *)treeNodeInfo
{
    UIColor *blackOpaque = [UIColor grayColor];
    blackOpaque = [blackOpaque colorWithAlphaComponent:0.75f];
    
    if (treeNodeInfo.treeDepthLevel == 0) {
        cell.backgroundColor = blackOpaque;
    } else if (treeNodeInfo.treeDepthLevel == 1) {
        cell.backgroundColor = blackOpaque;
    }
}

#pragma mark - Method to UserSetting

- (void)switchDefaultIMSetting:(id)sender
{
    UISwitch *obj = (UISwitch *)sender;
    RATreeView *treeView = (RATreeView *)[(REMenuItem *)[settingMenu.items objectAtIndex:0] customView];
    if (obj.isOn) {
        [treeView expandRowForItem:optionData[0] withRowAnimation:RATreeViewRowAnimationBottom];
    } else {
        [treeView collapseRowForItem:optionData[0] withRowAnimation:RATreeViewRowAnimationTop];
    }
    // Save setting to userinfo
    [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:obj.isOn] forKey:kIMDefaultKey];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:obj.isOn] forKey:kIMDefaultKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)switchAlbumSetting:(id)sender
{
    UISwitch *obj = (UISwitch *)sender;
    [[SettingVariable sharedInstance].variableDictionary setValue:[NSNumber numberWithBool:obj.isOn] forKey:kSaveAlbumKey];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:obj.isOn] forKey:kSaveAlbumKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    // Save setting to userinfo
}

@end
