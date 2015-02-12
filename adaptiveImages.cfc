<cfcomponent output="false">
<cfprocessingdirective pageEncoding="utf-8"/>
<cfscript>
function init
(
	required array resolutions 										// the resolution break-points to use (screen widths, in pixels, any order you like)
	,boolean cacheFileOperations=true							// cache source file paths and file existence tests to avoid unnecessary disk access
	,boolean checkForFileUpdates=false						// ensures updated source images are re-cached, but requires disk access on every request
	,numeric browserCacheSeconds=( 60*60*24*30 ) 	// how long the BROWSER cache should last (seconds, minutes, hours, days. 30 days by default)
	,numeric pixelDensityMultiplier=1.5						// by how much to multiply the resolution for "retina" displays. Number between 1 and 3
	,numeric jpgQuality=50 												// the quality of any generated JPGs on a scale of 1 to 100
	,boolean sharpen=true 												// Shrinking images can blur details, perform a sharpen on re-scaled images?
	,string interpolation="highPerformance"				// interpolation algorithm to use when scaling/resizing file
	,boolean writeLogs=false 											// whether or not to log activity - don't use in production
	,string logFilename="adaptive-images"					// name of logfile
)
{	
	variables.config	=	arguments;
	validateConfig( config );
	ArraySort( config.resolutions, "numeric","asc" );// smallest to largest
	config.smallestResolution			=	config.resolutions[ 1 ];
	config.largestResolution			=	config.resolutions[ ArrayLen( config.resolutions ) ];
	variables.fileOperationsCache	=	{};
	return this;
}

private void function validateConfig( required struct config ){
	var exceptionType	=	"AdaptiveImages.invalidConfiguration";
	if( !ArrayLen( config.resolutions ) )
		throw( type=exceptionType,message="At least one resolution must be specified" );
	if( !IsValid( "integer",config.browserCacheSeconds ) )
		throw( type=exceptionType,message="The browserCacheSeconds argument must be an integer" );
	if( !IsValid( "range",config.pixelDensityMultiplier,1,3 ) )
		throw( type=exceptionType,message="The pixelDensityMultiplier argument must be between 1 and 3" );
	if( !IsValid( "range",config.jpgQuality,1,100 ) )
		throw( type=exceptionType,message="The pixelDensityMultiplier argument must be between 1 and 100" );
}

/* The main public method to serve images */
/* Pass in the original requested URL as supplied by the URL Rewrite engine. For IIS7 this is cgi.HTTP_X_ORIGINAL_URL */
public function process( required string originalUrl ){
	try{
		var requestedFileUri 				= UrlDecode( originalUrl );
		var requestedFilename 			= ListLast( requestedFileUri, "/" );
		var	sourceFilePath 					= getSourceFilePath( requestedFileUri );
		var sourceFolderPath				=	GetDirectoryFromPath( sourceFilePath );
		var requestedFileExtension 	= ListLast( requestedFilename, "." );
		
		_log( "AI: Request for: #requestedFileUri# which translates to #sourceFilePath#" );
		
		var mimeType		=	mimeType( requestedFileExtension );
		var resolution	=	resolution();
		if( resolution GT config.largestResolution ){
			_log( "AI: Client resolution #resolution# is larger than largest configured resolution, so sending original" );
			return this.sendImage( sourceFilePath,mimeType );
		}
		var resolutionFolderName	= resolution;
		_log( "AI: Resolution set=#resolution#" );
		var cacheFolderPath	=	sourceFolderPath & resolutionFolderName & "/";
		var cachedFilePath 	= cacheFolderPath & requestedFilename;
		_log( "AI: Checking for cached file: #cachedFilePath#" );
		if( cachedFileExists( cachedFilePath ) ){
			if( !config.checkForFileUpdates ){ 
				_log( "AI: Sending cached file without checking for an updated source" );
				return this.sendImage( cachedFilePath,mimeType );
			} else if( !fileHasBeenUpdated( sourceFilePath,cachedFilePath ) ){
				_log( "AI: Sending cached file as source has not been updated" );
				return this.sendImage( cachedFilePath,mimeType );
			}
		}
		// not in cache, or has been updated, so continue
		var sourceImage	=	ImageRead( sourceFilePath );
		if( sourceImage.width LTE resolution ){ 
			// No need to downscale because the width of the source image is already less than the client width
			_log( "AI: Source width #sourceImage.width# is the same size or smaller than client resolution #resolution#" );
			return this.sendImage( sourceFilePath,mimeType );
		}
		var newImage	=	generateImage( sourceImage,resolution );
		ensureCacheFolderExists( cacheFolderPath );
		// save the new file in the appropriate path, and send a version to the browser
		ImageWrite( newImage,cachedFilePath,config.jpgQuality/100 );
		checkCachedImageIsNotLargerThanSource( cachedFilePath,sourceFilePath );
		// send image to client
		return this.sendImage( cachedFilePath,mimeType );
	}
	catch( any exception ){
		_log( "AI: Error Occured : #exception.message#" );
		header( status_text:"503:Temporary problem",abort:true );
	}
}

/* Inspect properties */
public struct function getFileOperationsCache(){
	return fileOperationsCache;
}

public struct function getConfig(){
	return config;
}

/* Private helper functions */

private void function checkCachedImageIsNotLargerThanSource( required string cachedFilePath,required string sourceFilePath ){
	cachedFileSize	=	GetFileInfo( cachedFilePath ).size;
	sourceFileSize	=	GetFileInfo( sourceFilePath ).size;
	if( cachedFileSize GT sourceFileSize ){
		_log( "AI: Scaled image is #( cachedFileSize - sourceFileSize )# bytes larger than the original. Copying original instead." );
		FileCopy( sourceFilePath,cachedFilePath );
	}
}

/* Resize the source image to the width of the resolution breakpoint we're working with */
private function generateImage( required sourceImage,required numeric resolution ){
	var newImage = sourceImage;
	ImageScaleToFit( newImage,resolution,"",config.interpolation );// height as empty string will cause aspect ratio to be maintained
	if( config.sharpen ){
		ImageSharpen( newImage );
	}
	return newImage;
}

private boolean function isMobile( required string userAgent=cgi.HTTP_USER_AGENT ){
	return FindNoCase( "mobile",userAgent );
}

private boolean function cookieIsValid(){
	return REFind( "^[0-9]+,[0-9\.]+$",cookie.resolution );
}

/* Send different defaults to mobile and desktop */
private numeric function defaultResolution(){
	return this.isMobile()? config.smallestResolution: config.largestResolution;
}

private numeric function resolution(){
	if( IsNull( cookie.resolution ) ){
		_log( "AI: Cookie not found" );
		return defaultResolution();
	}
	if( !cookieIsValid() ){
		_log( "AI: Invalid cookie deleted" );
		deleteCookie();
		return defaultResolution();
	}	
	_log( "AI: Cookie.resolution=#cookie.resolution#" );
	var cookieData	=	ListToArray( cookie.resolution );
	var clientWidth	=	cookieData[ 1 ];
	var	clientPixelDensity	=	cookieData[ 2 ];
	var maxImageWidth	=	clientWidth;
	// if pixel density greater than 1, then we need to be smart about adapting and fitting into the defined breakpoints
	if( clientPixelDensity GT 1 ){
		maxImageWidth	=	( clientWidth * config.pixelDensityMultiplier );
	}
	_log( "AI: maxImageWidth=#maxImageWidth#" );
	// actual resolution is bigger than largest defined resolution
	if( maxImageWidth GT config.largestResolution )
		return maxImageWidth;
	// otherwise return the matching or next highest defined breakpoint
	for( var thisResolution in config.resolutions){
		if( maxImageWidth LTE thisResolution )
			return thisResolution;
	}
	// fallback, should never run
	return config.largestResolution;
}

/* File/folder functions */

// Always use forward slashes for consistency
private string function forwardSlashes( required string path ){
	return Replace( path,"\","/","ALL" );
}

private string function getSourceFilePath( required string fileUri ){
	var filePath	=	forwardSlashes( ExpandPath( fileUri ) );
	if( !config.cacheFileOperations )
		return filePath;
	var cacheKey	=	REReplace( fileUri,"^/","" );// CF vars can't begin with a slash
	if( StructKeyExists( fileOperationsCache,cacheKey ) ){
		_log( "AI: Using cached source file path" );
		return fileOperationsCache[ cacheKey ].path;
	}
	fileOperationsCache[ cacheKey ]	=	{ path	=	filePath };
	return filePath;
}

private void function cachePathExistence( required string path ){
	if( !config.cacheFileOperations )
		return;
	fileOperationsCache[ path ]	=	true;
	_log( "AI: Caching existence flag for #path#" );
}

private boolean function cacheFolderExists( required string path ){
	if( !config.cacheFileOperations )
		return DirectoryExists( path );
	var cacheKey	=	path;
	if( StructKeyExists( fileOperationsCache,cacheKey ) ){
		_log( "AI: Using cached existence test for resolution cache folder" );
		return true;
	}
	var pathExists	=	DirectoryExists( path );
	if( pathExists ){
		cachePathExistence( path );
	}
	return pathExists;
}

private void function ensureCacheFolderExists( required string cacheFolderPath ){
	_log( "AI: Does #cacheFolderPath# exist? #cacheFolderExists( cacheFolderPath )#" );
	if( !cacheFolderExists( cacheFolderPath ) ){
		DirectoryCreate( cacheFolderPath );
		_log( "AI: Created #cacheFolderPath#" );
		cachePathExistence( cacheFolderPath );
	}
}

private boolean function cachedFileExists( required string path )
{
	if( !config.cacheFileOperations )
		return FileExists( path );
	if( StructKeyExists( fileOperationsCache,path ) ){
		_log( "AI: Using cached existence test for cached path" );
		return true;
	}
	var pathExists	=	 FileExists( path );
	if( pathExists ){
		cachePathExistence( path );
	}
	return pathExists;
}

//This check is expensive: disabled by default, but use if images change frequently and you are not using deleteCachedCopies() when performing updates
private boolean function fileHasBeenUpdated( required string sourceFilePath,required string cachedFilePath ){
	// get last modified of cached file
	var cacheDate  = GetFileInfo( cachedFilePath ).lastModified; 
	// get last modified of original
	var sourceDate = GetFileInfo( sourceFilePath ).lastModified;
	_log( "AI: Checking for source updates: Cached file modified: #cacheDate#, source file modified: #sourceDate#" );
	return ( cacheDate LT sourceDate );
}

/* END file/folder functions */

private string function mimeType( required string requestedFileExtension ){
	switch( requestedFileExtension ){ 
		case "png":
			return "image/png";
		case "gif":
			return "image/gif";
		case "jpg": case "jpeg": case "jpe":
			return "image/jpeg";
	}
	throw( type="AdaptiveImages.invalidFileExtension",message="The file requested has an invalid file extension: '#requestedFileExtension#'." )
}

private void function _log( required string text,string file=config.logFilename ){
	if( config.writeLogs ){
		WriteLog( file="#file#",text="#text#" )	
	}
}

/* Public Maintenance functions */
public void function clearFileOperationsCache(){
	if( !config.cacheFileOperations )
		return;
	StructClear( fileOperationsCache );
}

/* I delete any cached copies for the specified source image - use me when deleting or updating a source image */
public void function deleteCachedCopies( required string imageFullPath ){
	if( !FileExists( imageFullPath ) )
		return;
	imageFullPath	=	forwardSlashes( imageFullPath );
	var sourceFolderPath	=	GetDirectoryFromPath( imageFullPath );
	for( var resolution in config.resolutions ){
		var cachedFile	=	sourceFolderPath & resolution & "/" & GetFileFromPath( imageFullPath );
		if( FileExists( cachedFile ) ){
			FileDelete( cachedFile );
		}
	}
	clearFileOperationsCache();
}

/* I delete any cached images where the source no longer exists */
public void function cleanupCacheFolders( required string sourceImageFolder ){
	var sourceFolderPath	=	ExpandPath( sourceImageFolder );
	var sourceFiles	=	DirectoryList( sourceFolderPath,false,"name" );
	var cachedImages	=	[];
	for( var resolution in config.resolutions ){
		var resolutionFolderPath	=	sourceFolderPath & resolution & "/";
		if( !DirectoryExists( resolutionFolderPath ) )
			continue;
		cachedImages	=	DirectoryList( resolutionFolderPath,false,"name" );
		for( var image in cachedImages ){
			if( !ArrayFindNoCase( sourceFiles,image ) ){
				FileDelete( resolutionFolderPath & image );
			}
		}
	}
}
</cfscript>

<cffunction name="header" access="private" returntype="void" output="false">
	<cfargument name="nameValue" type="string">
	<cfargument name="statusText" type="string">
	<cfargument name="abort" type="boolean" default="false">
	<cfif StructKeyExists( arguments,"nameValue" ) AND Len( arguments.nameValue )>
		<cfheader name="#Trim( ListFirst( arguments.nameValue,":" ) )#" value="#ListRest( arguments.nameValue,":" )#">
	<cfelseif StructKeyExists( arguments,"statusText" ) AND Len( arguments.statusText )>
		<cfheader statuscode="#Trim( ListFirst( arguments.statusText,":" ) )#" statustext="#ListRest( arguments.statusText,":" )#">
	</cfif>
	<cfif arguments.abort>
		<cfabort>
	</cfif>
</cffunction>

<cffunction name="deleteCookie" returntype="void" access="private" output="false">
	<cfcookie name="resolution" value="deleted" expires="now"><!--- Change value to make testable --->
</cffunction>

<cffunction name="sendImage" access="private" returntype="void" output="false">
	<cfargument name="filepath" type="string" required="true">
	<cfargument name="mimeType" type="string" required="true">
	<cfargument name="browserCacheSeconds" default="#config.browserCacheSeconds#">
	<cfscript>
		header( "Content-type:#mimeType#" );
		if( IsNumeric( browserCacheSeconds ) ){
			header( "Cache-Control:private,max-age=#browserCacheSeconds#" );
		}
		var fileInfo = GetFileInfo( filepath );
		header( "Content-Length:#fileInfo.size#" );
	</cfscript>
	<cfcontent file="#filepath#" type="#mimeType#">
	<cfabort>
</cffunction>
</cfcomponent>