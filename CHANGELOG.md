## 2.1.3 - 8 November 2017
- \#7 Handle errors caused by file system being out of sync with file operations cache

## 2.1.2 - 2 October 2017
- Enhancements
	- \#5 Add option to log errors only
- Fixes
	- \#6 Query strings in original URL causes errors.

## 2.0.1 - 19 September 2017
- Fixes
	- \#4 Tomcat appears not to be able to read javascript set cookies containing commas
	- Cached folder cleanup not working properly in tests under ACF11
- Other
	- Add locking around file/directory deletion operations

## 2.0.0 - 8 September 2017
- Enhancements
	- \#2 Add `cacheFolderName` config option
- Fixes
	- \#3 `cleanupCacheFolders()` should delete any empty resolution cache folders
- Breaking changes
	- Remove support for ColdFusion 10 and below, and Railo.
	- Change to positional init arguments with new `cacheFolderName` option
- Other
	- Rewrite tests using TestBox BDD style

## 1.0.2 - 12 February 2015
- Replace MX Unit with Testbox in MX Unit style

## 1.0.0 - 27 November 2013
- Initial release