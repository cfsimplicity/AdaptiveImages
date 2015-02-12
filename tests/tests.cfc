<cfcomponent extends="mxunit.framework.TestCase" output="false">
<!--- 
	Requirements for running test suite:
		TestBox 2.1+ https://github.com/Ortus-Solutions/TestBox
		Application mapping for /testbox
		Web server directory (virtual or real) for /adaptiveImages
 --->
<cfscript>
void function beforeTests(){
	variables.imageFolderUrl	=	"/root/tests/images/";
	variables.imageFolderPath	=	forwardSlashes( ExpandPath( imageFolderUrl ) );
	variables.imageFilename	=	"test.jpg";
	variables.sourceImageUrl	=	imageFolderUrl & imageFilename;
	variables.sourceImagePath	=	forwardSlashes( ExpandPath( sourceImageUrl ) );
	variables.sourceImageUrlCacheKey	=	REReplace( sourceImageUrl,"^/","" );
}

void function afterTests(){
	deleteResolutionCookie();
}

void function setUp(){
	variables.ai	=	New root.adaptiveImages( [ "480","320" ] );
}

void function tearDown(){}

/* Injectables */

private boolean function returnTrue(){
	return true;
}

private boolean function returnFalse(){
	return false;
}

private void function setFileOperationsCacheValue( required key,required value ){
	fileOperationsCache[ key ]	=	value;
}

private string function sendImage( filepath ){
	//can't test actual sending, so just return the selected image path
	return filepath;
}

/* Tests */
public void function test_init_throwsException_ifNoResolutionsDefined(){
	expectedException( "AdaptiveImages.invalidConfiguration" );
	variables.ai	=	New root.adaptiveImages( [] );
}

public void function test_init_throwsException_ifBrowserCacheSecondsIsNotAnInteger(){
	expectedException( "AdaptiveImages.invalidConfiguration" );
	variables.ai	=	New root.adaptiveImages( resolutions=[ "480" ],browserCacheSeconds=5.1 );
}

public void function test_init_throwsException_ifPixelDensityMultiplierIsInvalid(){
	expectedException( "AdaptiveImages.invalidConfiguration" );
	variables.ai	=	New root.adaptiveImages( resolutions=[ "480" ],pixelDensityMultiplier=0 );
}

public void function test_init_throwsException_ifJpegQualityIsInvalid(){
	expectedException( "AdaptiveImages.invalidConfiguration" );
	variables.ai	=	New root.adaptiveImages( resolutions=[ "480" ],jpgQuality=0 );
}

public void function test_init_sortsResolutions_smallestFirst(){
	var config	=	ai.getConfig();
	Assert( config.smallestResolution LT config.largestResolution,"smallest resolution should be smaller than largest" );
}

public void function test_getSourceFilePath_returnsPath_romAValidSourceImageUrl(){
	makePublic( ai,"getSourceFilePath" );
	var expected	=	imageFolderPath & "test.jpg";
	var actual		=	ai.getSourceFilePath( sourceImageUrl );
	Assert( actual IS expected,"path returned should be #expected#" );
}

public void function test_getSourceFilePath_cachesPath_byDefault(){
	makePublic( ai,"getSourceFilePath" );
	var cache	=	ai.getFileOperationsCache();
	var sourceFilePath	=	ai.getSourceFilePath( sourceImageUrl );
	Assert( StructKeyExists( cache,sourceImageUrlCacheKey ),"uri should be cached" );
	var expected	=	imageFolderPath & "test.jpg";
	var actual	=	cache[ sourceImageUrlCacheKey ].path;
	Assert( actual IS expected,"path returned should be #expected#" );
}

public void function test_mimeType_handlesGifJpegAndPng(){
	makePublic( ai,"mimeType" );
	Assert( ai.mimeType( "gif" ) IS "image/gif","should handle gif" );
	Assert( ai.mimeType( "jpe" ) IS "image/jpeg","should handle jpe" );
	Assert( ai.mimeType( "jpg" ) IS "image/jpeg","should handle jpg" );
	Assert( ai.mimeType( "png" ) IS "image/png","should handle png" );
}

public void function test_mimeType_throwsException_onInvalidFileExtension(){
	expectedException( "AdaptiveImages.invalidFileExtension" );
	makePublic( ai,"mimeType" );
	ai.mimeType( ".doc" );
}

public void function test_isMobile_findsMobile_anywhereInString(){
	makePublic( ai,"isMobile" );
	Assert( NOT ai.isMobile( "Mozilla/5.0 (Windows NT 6.1; rv:23.0) Gecko/20100101 Firefox/23.0 " ),"user agent without the string 'mobile' shouldn't be treated as mobile" );
	Assert( ai.isMobile( "Mozilla/5.0 (compatible; MSIE 9.0; Windows Phone OS 7.5; Trident/5.0; IEMobile/9.0)" ),"user agent including 'mobile' should be treated as mobile" );
}

public void function test_cookieIsValid_works(){
	makePublic( ai,"cookieIsValid" );
	var validValue	=	"480,0";
	var invalidValue	=	"abc";
	setResolutionCookie( validValue );
	Assert( ai.cookieIsValid() );
	setResolutionCookie( invalidValue );
	Assert( NOT ai.cookieIsValid() );
}

public void function test_deleteCookie_works(){
	makePublic( ai,"deleteCookie" );
	setResolutionCookie( "480,0" );
	Assert( StructKeyExists( cookie,"resolution" ),"resolution cookie should have been set" );
	ai.deleteCookie();
	Assert( cookie.resolution IS "deleted","resolution cookie should have been 'deleted'" );// Can't test deletion on same request but deleteCookie will also change value: test that.
}

public void function test_defaultResolution_returnsSmallest_forMobile(){
	makePublic( ai,"defaultResolution" );
	injectMethod( ai,this,"returnTrue","isMobile" );
	var config	=	ai.getConfig();
	Assert( ai.defaultResolution() IS config.smallestResolution );
}

public void function test_defaultResolution_returnsLargest_forNonMobile(){
	makePublic( ai,"defaultResolution" );
	injectMethod( ai,this,"returnFalse","isMobile" );
	var config	=	ai.getConfig();
	Assert( ai.defaultResolution() IS config.largestResolution );
}

public void function test_resolution_returnsRetinaResolution_exceedingLargestDefined(){
	variables.ai	=	New root.adaptiveImages( resolutions=[ 320,480 ],pixelDensityMultiplier=1.5 );
	makePublic( ai,"resolution" );
	setResolutionCookie( "500,2" );// set as retina display so multiplier is applied
	Assert( ai.resolution() EQ 750 );//multiplier is 1.5 so 500x1.5. Bigger than largest defined
}

public void function test_resolution_returnsRetinaResolution_atOrBelowLargestDefined(){
	variables.ai	=	New root.adaptiveImages( resolutions=[ 320,480,1024 ],pixelDensityMultiplier=1.5 );
	makePublic( ai,"resolution" );
	setResolutionCookie( "300,2" );// set as retina display so multiplier is applied
	Assert( ai.resolution() EQ 480 );// retina resolution is 450. Expect next highest defined
}

public void function test_resolution_returnsNonRetinaResolution_exceedingLargestDefined(){
	makePublic( ai,"resolution" );
	setResolutionCookie( "500,1" );//non-retina
	Assert( ai.resolution() EQ 500 );// client width is bigger than largest defined
}

public void function test_resolution_returnsNonRetinaResolution_atOrBelowLargestDefined(){
	makePublic( ai,"resolution" );
	setResolutionCookie( "300,1" );
	Assert( ai.resolution() EQ 320 );
}

public void function test_process_sendsSourceImage_ifResolutionExceedsLargestDefined(){
	injectMethod( ai,this,"sendImage" );
	setResolutionCookie( "500,1" );
	Assert( ai.process( sourceImageUrl ) IS sourceImagePath );
}

public void function test_cachedFileExists_detectsAndCachesCachedFileExistence(){
	makePublic( ai,"cachedFileExists" );
	var cacheFilePath	=	createCachedFile( 300 );
	Assert( ai.cachedFileExists( cacheFilePath ),"existence of cached file should be detected" );
	var cache	=	ai.getFileOperationsCache();
	Assert( StructKeyExists( cache,cacheFilePath),"path of cached file should now be in fileOperationsCache" );
	deleteFolder( GetDirectoryFromPath( cacheFilePath ) );
}

public void function test_process_sendsCachedImage_ifItExists(){
	injectMethod( ai,this,"sendImage" );
	injectMethod( ai,this,"setFileOperationsCacheValue" );
	makePublic( ai,"cachedFileExists" );
	var cacheFilePath	=	createCachedFile( 320 );
	ai.setFileOperationsCacheValue( cacheFilePath,true );
	setResolutionCookie( "300,1" );
	Assert( ai.process( sourceImageUrl ) IS cacheFilePath );
	deleteFolder( GetDirectoryFromPath( cacheFilePath ) );
}

public void function test_process_sendsSourceImage_ifResolutionExceedsSourceWidth(){
	injectMethod( ai,this,"sendImage" );
	// test image is 600px wide
	setResolutionCookie( "700,1" );
	Assert( ai.process( sourceImageUrl ) IS sourceImagePath );
}

public void function test_generateImage_resizes_toSpecifiedWidth(){
	var sourceImage	=	ImageRead( sourceImagePath );
	makePublic( ai,"generateImage" );
	var resizedImage	=	ai.generateImage( sourceImage,320 );
	Assert( resizedImage.width EQ	320 );
}

public void function test_ensureCacheFolderExists_createsCacheFolderAndCachesPath(){
	makePublic( ai,"ensureCacheFolderExists" );
	var cacheFolderPath	=	imageFolderPath & 320 & "/";
	deleteFolder( cacheFolderPath );//ensure it doesn't exist.
	ai.ensureCacheFolderExists( cacheFolderPath );
	Assert( DirectoryExists( cacheFolderPath ) );
	var cache	=	ai.getFileOperationsCache();
	Assert( StructKeyExists( cache,cacheFolderPath),"path of cache folder should now be in fileOperationsCache" );
	deleteFolder( cacheFolderPath );
}

public void function test_checkCachedImageIsNotLargerThanSource_cachesCopyOfSource_ifResizedImageIsLarger(){
	makePublic( ai,"checkCachedImageIsNotLargerThanSource" );
	var largerTestImagePath	=	imageFolderPath & "largerFileSizeThanSource.jpg";
	var cacheFolderPath	=	imageFolderPath & 320 & "/";
	deleteFolder( cacheFolderPath );//ensure it doesn't exist.
	DirectoryCreate( cacheFolderPath );
	cachedFilePath	=	cacheFolderPath & "test.jpg";
	FileCopy( largerTestImagePath,cachedFilePath );
	ai.checkCachedImageIsNotLargerThanSource( cachedFilePath,sourceImagePath );
	var expected	=	GetFileInfo( sourceImagePath ).size;
	var actual		=	GetFileInfo( cachedFilePath ).size;
	Assert( actual IS expected );
	deleteFolder( cacheFolderPath );
}

public void function test_process_cachesAndSendsImageSizedToResolution_ifNotInCache(){
	injectMethod( ai,this,"sendImage" );
	var cacheFolderPath	=	imageFolderPath & 320 & "/";
	var cacheFilePath	=	cacheFolderPath & "test.jpg";
	deleteFolder( cacheFolderPath );//ensure it doesn't exist.
	setResolutionCookie( "300,1" );
	Assert( ai.process( sourceImageUrl ) IS cacheFilePath );
	deleteFolder( cacheFolderPath );
}
/* END tests */

/* Helpers */
private string function forwardSlashes( required string path ){
	return Replace( path,"\","/","ALL" );
}

private string function createCachedFile( resolution=300 ){
	var filePath	=	imageFolderPath & resolution & "/" & imageFilename;
	createFile( filePath );
	return filePath;
}

private void function createFile( path ){
	var folderPath	=	GetDirectoryFromPath( path );
	if( !DirectoryExists( folderPath ) )
		DirectoryCreate( folderPath );
	if( !FileExists( path ) ){
		FileWrite( path,"test" );
	}
}

private void function deleteFolder( path ){
	if( DirectoryExists( path ) )
		DirectoryDelete( path,true );
}
</cfscript>

<cffunction name="setResolutionCookie" access="private" returntype="void" output="false">
	<cfargument name="value" required="true">
	<cfcookie name="resolution" value="#value#"/>
</cffunction>

<cffunction name="deleteResolutionCookie" access="private" returntype="void" output="false">
	<cfcookie name="resolution" value="deleted" expires="now"/>
</cffunction>

</cfcomponent>