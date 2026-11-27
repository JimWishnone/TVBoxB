#import "MainViewController+Private.h"

@implementation MainViewController (Tables)

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.sidebar) return (NSInteger)self.sidebarItems.count;
    if (tableView == self.liveTable) return (NSInteger)self.displayedLiveChannels.count;
    if (tableView == self.sourcesTable) return (NSInteger)self.sourceRows.count;
    if (tableView == self.historyTable) return (NSInteger)self.historyItems.count;
    if (tableView == self.favoritesTable) return (NSInteger)self.favoritesItems.count;
    if (tableView == self.programTable) return (NSInteger)self.programModalItems.count;
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.programTable) {
        NSString *identifier = [@"Program-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.programModalItems.count) {
            TVLiveProgram *program = self.programModalItems[row];
            if ([tableColumn.identifier isEqualToString:@"time"]) {
                NSString *start = program.startTime ?: @"";
                NSString *end = program.endTime ?: @"";
                cell.textField.stringValue = (start.length > 0) ? [NSString stringWithFormat:@"%@ - %@", start, end] : start;
            } else {
                cell.textField.stringValue = program.title ?: @"";
            }
        }
        return cell;
    }

    if (tableView == self.sidebar) {
        NSString *identifier = @"SidebarCell";
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSImageView *imageView = [[NSImageView alloc] init];
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            [cell addSubview:imageView];
            cell.imageView = imageView;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.font = [NSFont systemFontOfSize:13];
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
                [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [imageView.widthAnchor constraintEqualToConstant:18],
                [imageView.heightAnchor constraintEqualToConstant:18],
                [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:6],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.sidebarItems.count) {
            cell.textField.stringValue = self.sidebarItems[row];
            cell.imageView.image = [self sidebarIconForRow:row];
        }
        return cell;
    }

    if (tableView == self.sourcesTable) {
        NSString *identifier = [@"Source-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.sourceRows.count) {
            NSDictionary *sourceRow = self.sourceRows[row];
            if ([tableColumn.identifier isEqualToString:@"status"]) {
                NSString *status = sourceRow[@"status"] ?: @"检查中";
                cell.textField.stringValue = status;
                if ([status isEqualToString:@"可用"]) {
                    cell.textField.textColor = [NSColor systemGreenColor];
                } else if ([status isEqualToString:@"不可用"]) {
                    cell.textField.textColor = [NSColor systemRedColor];
                } else {
                    cell.textField.textColor = [NSColor secondaryLabelColor];
                }
            } else {
                cell.textField.stringValue = sourceRow[tableColumn.identifier] ?: @"";
                cell.textField.textColor = [NSColor labelColor];
            }
        }
        return cell;
    }

    if (tableView == self.historyTable) {
        NSString *identifier = [@"History-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.historyItems.count) {
            TVHistoryItem *item = self.historyItems[row];
            NSString *colID = tableColumn.identifier;
            if ([colID isEqualToString:@"name"]) {
                cell.textField.stringValue = item.title ?: @"";
            } else if ([colID isEqualToString:@"type"]) {
                cell.textField.stringValue = item.isLive ? @"直播" : @"点播";
            } else if ([colID isEqualToString:@"detail"]) {
                cell.textField.stringValue = item.subtitle ?: @"";
            } else if ([colID isEqualToString:@"progress"]) {
                cell.textField.stringValue = [self formatPlaybackTime:item.playbackTime];
            } else if ([colID isEqualToString:@"date"]) {
                cell.textField.stringValue = [self formatHistoryDate:item.date];
            }
        }
        return cell;
    }

    if (tableView == self.favoritesTable) {
        if ([tableColumn.identifier isEqualToString:@"name"]) {
            TVFavoriteCellView *cell = [tableView makeViewWithIdentifier:@"favorite-name" owner:self];
            if (!cell) {
                cell = [[TVFavoriteCellView alloc] initWithFrame:NSMakeRect(0, 0, 300, 36)];
                cell.identifier = @"favorite-name";
            }
            if (row < (NSInteger)self.favoritesItems.count) {
                TVFavoriteItem *item = self.favoritesItems[row];
                cell.nameLabel.stringValue = item.title ?: @"";
                __weak typeof(self) weakSelf = self;
                cell.onDelete = ^{
                    [weakSelf removeFavoriteAtIndex:row];
                };
            }
            return cell;
        }

        NSString *identifier = [@"Favorite-" stringByAppendingString:tableColumn.identifier];
        NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = identifier;
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            [cell addSubview:textField];
            cell.textField = textField;
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }
        if (row < (NSInteger)self.favoritesItems.count) {
            TVFavoriteItem *item = self.favoritesItems[row];
            if ([tableColumn.identifier isEqualToString:@"type"]) {
                cell.textField.stringValue = item.isLive ? @"直播" : @"点播";
            } else if ([tableColumn.identifier isEqualToString:@"detail"]) {
                cell.textField.stringValue = item.subtitle ?: @"";
            }
        }
        return cell;
    }

    if (tableView == self.liveTable && [tableColumn.identifier isEqualToString:@"icon"]) {
        TVLiveIconCell *cell = [tableView makeViewWithIdentifier:@"icon" owner:self];
        if (!cell) {
            cell = [[TVLiveIconCell alloc] initWithFrame:NSMakeRect(0, 0, 36, 32)];
            cell.identifier = @"icon";
        }
        if (row < (NSInteger)self.displayedLiveChannels.count) {
            TVLiveChannel *channel = self.displayedLiveChannels[row];
            cell.channelKey = channel.name;
            cell.iconView.image = TVLetterIcon(channel.name);
            [self loadLiveLogoForChannel:channel intoCell:cell];
        }
        return cell;
    }

    if (tableView == self.liveTable && [tableColumn.identifier isEqualToString:@"channel"]) {
        TVChannelCellView *cell = [tableView makeViewWithIdentifier:@"channel" owner:self];
        if (!cell) {
            cell = [[TVChannelCellView alloc] initWithFrame:NSMakeRect(0, 0, 320, 32)];
            cell.identifier = @"channel";
        }
        if (row < (NSInteger)self.displayedLiveChannels.count) {
            TVLiveChannel *channel = self.displayedLiveChannels[row];
            __weak typeof(self) weakSelf = self;
            cell.nameLabel.stringValue = channel.name ?: @"";
            cell.programLink.hidden = (channel.programs.count == 0);
            [cell refreshHoverState];
            cell.favorited = ([weakSelf favoriteIndexForLiveChannel:channel] != NSNotFound);
            cell.onProgramClick = ^{
                [weakSelf showProgramScheduleForChannel:channel];
            };
            cell.onFavoriteClick = ^{
                [weakSelf toggleLiveChannelFavorite:channel];
            };
        }
        return cell;
    }

    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = identifier;
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:textField];
        cell.textField = textField;
        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if (row < (NSInteger)self.displayedLiveChannels.count) {
        TVLiveChannel *channel = self.displayedLiveChannels[row];
        if ([identifier isEqualToString:@"channel"]) {
            cell.textField.stringValue = channel.name ?: @"";
        } else if ([identifier isEqualToString:@"group"]) {
            cell.textField.stringValue = channel.group ?: @"";
        } else if ([identifier isEqualToString:@"sources"]) {
            cell.textField.stringValue = channel.sourceNames ?: @"";
        } else if ([identifier isEqualToString:@"lines"]) {
            cell.textField.stringValue = [NSString stringWithFormat:@"%lu 线路", (unsigned long)channel.lines.count];
        }
    }
    return cell;
}

- (void)loadLiveLogoForChannel:(TVLiveChannel *)channel intoCell:(TVLiveIconCell *)cell {
    if (channel.logo.length == 0) return;
    [TVImageLoader loadImageAtURL:channel.logo completion:^(NSImage * _Nullable image) {
        if (image && [cell.channelKey isEqualToString:channel.name]) {
            cell.iconView.image = image;
        }
    }];
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    if (tableView != self.liveTable) return;
    self.liveSortDescriptor = tableView.sortDescriptors.firstObject;
    [self applyLiveFilterAndSort];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.sidebar) {
        NSInteger row = tableView.selectedRow;
        if (row >= 0) {
            [self showContentViewAtIndex:row];
        }
    }
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (collectionView == self.vodCollectionView) return (NSInteger)self.videos.count;
    if (collectionView == self.searchCollectionView) return (NSInteger)self.searchResults.count;
    return 0;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    VODCollectionItem *item = (VODCollectionItem *)[collectionView makeItemWithIdentifier:kVODItemIdentifier forIndexPath:indexPath];

    NSArray<TVVideo *> *sourceArray = nil;
    if (collectionView == self.vodCollectionView) sourceArray = self.videos;
    if (collectionView == self.searchCollectionView) sourceArray = self.searchResults;

    if (sourceArray && indexPath.item < (NSInteger)sourceArray.count) {
        [item configureWithVideo:sourceArray[indexPath.item]];
    }
    return item;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath) return;

    if (collectionView == self.vodCollectionView) {
        if (indexPath.item < (NSInteger)self.videos.count) {
            [self openVideo:self.videos[indexPath.item] site:[self selectedSiteForPopup:self.sitePopup]];
        }
    } else if (collectionView == self.searchCollectionView) {
        if (indexPath.item < (NSInteger)self.searchResults.count) {
            TVVideo *video = self.searchResults[indexPath.item];
            [self openVideo:video site:video.sourceSite];
        }
    }

    // 处理完点击后取消选中，确保再次单击同一视频仍能触发选中回调。
    // 注意：不能在选中回调内部同步修改选中状态，否则会触发 AppKit 的重入，
    // 导致 openVideo 被重复调用、重复弹出详情模态窗，进而使“取消/播放”按钮失效。
    NSSet<NSIndexPath *> *selected = [indexPaths copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [collectionView deselectItemsAtIndexPaths:selected];
    });
}


@end
