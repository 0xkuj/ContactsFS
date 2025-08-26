export TARGET = iphone:clang:14.5:14.5

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ContactsFS
GO_EASY_ON_ME = 1
ContactsFS_FILES = CFSRootListController.m CFSTerminalViewController.m
ContactsFS_FRAMEWORKS = UIKit
ContactsFS_PRIVATE_FRAMEWORKS = Preferences
ContactsFS_INSTALL_PATH = /Library/PreferenceBundles
ContactsFS_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
