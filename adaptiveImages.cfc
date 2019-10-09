component{

	variables.version = "2.1.4";
	variables.isACF = ( server.coldfusion.productname IS "ColdFusion Server" );
	variables.isLucee = ( server.coldfusion.productname IS "Lucee" );

	function init(
		required array resolutions // the resolution break-points to use (screen widths, in pixels, any order you like)
		,boolean cacheFileOperations = true // cache source file paths and file existence tests to avoid unnecessary disk access
		,boolean checkForFileUpdates = false // ensures updated source images are re-cached, but requires disk access on every request
		,string cacheFolderName = "" // sub-folder in which to store the resized images
		,numeric browserCacheSeconds = 2592000 // how long the BROWSER cache should last (30 days by default)
		,numeric pixelDensityMultiplier = 1.5 // by how much to multiply the resolution for "retina" displays. Number between 1 and 3
		,numeric jpgQuality = 50 // the quality of any generated JPGs on a scale of 1 to 100
		,boolean sharpen = true // Shrinking images can blur details, perform a sharpen on re-scaled images?
		,string interpolation = "highPerformance" // interpolation algorithm to use when scaling/resizing file
		,boolean writeLogs = false // whether or not to log activity - don't use in production
		,string logFilename = "adaptive-images" // name of logfile
		,boolean logErrors = arguments.writeLogs //with writeLogs false, just log errors from the process() method
	)
	{	
		variables.config = arguments;
		config.cacheFolderName = Trim( cacheFolderName ); //ensure it's a string
		variables.hasCacheFolderName = config.cacheFolderName.Len();
		validateConfig( config );
		ArraySort( config.resolutions, "numeric", "asc" );// smallest to largest
		config.smallestResolution = config.resolutions[ 1 ];
		config.largestResolution = config.resolutions[ ArrayLen( config.resolutions ) ];
		variables.fileOperationsCache = {};
		return this;
	}

	/* The main public method to serve images */
	/* Pass in the original requested URL as supplied by the URL Rewrite engine. For IIS this is cgi.HTTP_X_ORIGINAL_URL */
	public function process( required string originalUrl ){
		try{
			var requestedFileUri = cleanupUrl( originalUrl );
			var requestedFilename = ListLast( requestedFileUri, "/" );
			var sourceFilePath = getSourceFilePath( requestedFileUri );
			var sourceFolderPath = GetDirectoryFromPath( sourceFilePath );
			var requestedFileExtension = ListLast( requestedFilename, "." );
			_log( "AI: Request for: #requestedFileUri# which translates to #sourceFilePath#" );
			var mimeType = mimeType( requestedFileExtension );
			var resolution = resolution();
			if( resolution GT config.largestResolution ){
				_log( "AI: Client resolution #resolution# is larger than largest configured resolution, so sending original" );
				return sendImage( sourceFilePath, mimeType );
			}
			var resolutionFolderName = resolutionFolderName( resolution );
			_log( "AI: Resolution set=#resolution#" );
			var cacheFolderPath = sourceFolderPath & resolutionFolderName & "/";
			var cachedFilePath = cacheFolderPath & requestedFilename;
			_log( "AI: Checking for cached file: #cachedFilePath#" );
			if( cachedFileExists( cachedFilePath ) ){
				if( !config.checkForFileUpdates ){ 
					_log( "AI: Sending cached file without checking for an updated source" );
					return sendImage( cachedFilePath, mimeType );
				}
				else if( !fileHasBeenUpdated( sourceFilePath, cachedFilePath ) ){
					_log( "AI: Sending cached file as source has not been updated" );
					return sendImage( cachedFilePath, mimeType );
				}
			}
			// not in cache, or has been updated, so continue
			var sourceImage	= ImageRead( sourceFilePath );
			if( sourceImage.width LTE resolution ){ 
				// No need to downscale because the width of the source image is already less than the client width
				_log( "AI: Source width #sourceImage.width# is the same size or smaller than client resolution #resolution#" );
				return sendImage( sourceFilePath, mimeType );
			}
			var newImage = generateImage( sourceImage, resolution );
			ensureCacheFolderExists( cacheFolderPath );
			// save the new file in the appropriate path, and send a version to the browser
			ImageWrite( newImage, cachedFilePath, config.jpgQuality / 100 );
			checkCachedImageIsNotLargerThanSource( cachedFilePath, sourceFilePath );
			// send image to client
			return sendImage( cachedFilePath, mimeType );
		}
		catch( any exception ){
			if( !DirectoryExists( cacheFolderPath ) OR !FileExists( cachedFilePath ) ){
				if( config.logErrors OR config.writeLogs )
					WriteLog( file: config.logFilename, text: "AI: Error Occured : cached image should exist according to FO cache but is missing. Clearing FO cache." );
				clearFileOperationsCache();
			}
			else {
				if( config.logErrors OR config.writeLogs )
					WriteLog( file: config.logFilename, text: "AI: Error Occured : #exception.message#" );
				cfheader( statuscode: "503", statustext: "Temporary problem" );
				abort;
			}
		}
	}

	/* Inspect properties */
	public struct function getFileOperationsCache(){
		return fileOperationsCache;
	}

	public struct function getConfig(){
		return config;
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
		var sourceFolderPath = GetDirectoryFromPath( imageFullPath );
		for( var resolution in config.resolutions ){
			var cachedFile	=	sourceFolderPath & resolutionFolderName( resolution ) & "/" & GetFileFromPath( imageFullPath );
			if( FileExists( cachedFile ) ){
				lock name=cachedFile timeout=5 {
					FileDelete( cachedFile );
				}
			}
		}
		clearFileOperationsCache();
	}

	/* I delete any cached images where the source no longer exists */
	public void function cleanupCacheFolders( required string sourceImageFolder ){
		var sourceFolderPath = ExpandPath( sourceImageFolder );
		var sourceFiles = DirectoryList( sourceFolderPath, false, "name" );
		var cachedImages = [];
		for( var resolution in config.resolutions ){
			var resolutionFolderPath = sourceFolderPath & resolutionFolderName( resolution ) & "/";
			if( !DirectoryExists( resolutionFolderPath ) )
				continue;
			cachedImages = DirectoryList( resolutionFolderPath, false, "name" );
			if( ArrayLen( cachedImages ) ){
				for( var image in cachedImages ){
					if( !ArrayFindNoCase( sourceFiles, image ) ){
						var imagePath = resolutionFolderPath & image;
						lock name=imagePath timeout=5 {
							FileDelete( imagePath );
						}
					}
				}
				// See if there are any images left
				cachedImages = DirectoryList( resolutionFolderPath, false, "name" );
			}
			// Delete empty resolution folders
			if( !ArrayLen( cachedImages ) ){
				lock name=resolutionFolderPath timeout=5 {
					DirectoryDelete( resolutionFolderPath );
				}
			}
		}
	}

	/* Private helper functions */

	private void function validateConfig( required struct config ){
		var exceptionType	=	"AdaptiveImages.invalidConfiguration";
		if( !ArrayLen( config.resolutions ) )
			throw( type: exceptionType,message: "At least one resolution must be specified" );
		if( !IsValid( "integer", config.browserCacheSeconds ) )
			throw( type: exceptionType, message: "The browserCacheSeconds argument must be an integer" );
		if( !IsValid( "range", config.pixelDensityMultiplier, 1, 3 ) )
			throw( type: exceptionType, message: "The pixelDensityMultiplier argument must be between 1 and 3" );
		if( !IsValid( "range", config.jpgQuality, 1, 100 ) )
			throw( type: exceptionType, message: "The pixelDensityMultiplier argument must be between 1 and 100" );
	}

	private void function checkCachedImageIsNotLargerThanSource( required string cachedFilePath, required string sourceFilePath ){
		cachedFileSize = _GetFileInfo( cachedFilePath ).size;
		sourceFileSize = _GetFileInfo( sourceFilePath ).size;
		if( cachedFileSize GT sourceFileSize ){
			_log( "AI: Scaled image is #( cachedFileSize - sourceFileSize )# bytes larger than the original. Copying original instead." );
			FileCopy( sourceFilePath, cachedFilePath );
		}
	}

	/* Resize the source image to the width of the resolution breakpoint we're working with */
	private function generateImage( required sourceImage, required numeric resolution ){
		var newImage = sourceImage;
		ImageScaleToFit( newImage, resolution, "", config.interpolation );// height as empty string will cause aspect ratio to be maintained
		if( config.sharpen )
			ImageSharpen( newImage );
		return newImage;
	}

	private boolean function isMobile( required string userAgent = cgi.HTTP_USER_AGENT ){
		return FindNoCase( "mobile", userAgent );
	}

	private boolean function cookieIsValid(){
		return REFind( "^[0-9]+[,-][0-9\.]+$", cookie.resolution );
	}

	/* Send different defaults to mobile and desktop */
	private numeric function defaultResolution(){
		return isMobile()? config.smallestResolution: config.largestResolution;
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
		var cookieData = ListToArray( cookie.resolution, ",-" );// Hyphen more reliable, but allow either separator
		var clientWidth = cookieData[ 1 ];
		var	clientPixelDensity = cookieData[ 2 ];
		var maxImageWidth = clientWidth;
		// if pixel density greater than 1, then we need to be smart about adapting and fitting into the defined breakpoints
		if( clientPixelDensity GT 1 )
			maxImageWidth = ( clientWidth * config.pixelDensityMultiplier );
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

	private string function resolutionFolderName( required numeric resolution ){
		if( !hasCacheFolderName )
			return resolution;
		return config.cacheFolderName & "/" & resolution;
	}

	/* File/folder functions */

	// Always use forward slashes for consistency
	private string function forwardSlashes( required string path ){
		return path.Replace( "\", "/", "ALL" );
	}

	private string function cleanupUrl( required string originalUrl ){
		// remove any query string
		return ListFirst( UrlDecode( originalUrl ), "?" );
	}

	private string function getSourceFilePath( required string fileUri ){
		var filePath = forwardSlashes( ExpandPath( fileUri ) );
		if( !config.cacheFileOperations )
			return filePath;
		var cacheKey = fileUri.REReplace( "^/", "" );// CF vars can't begin with a slash
		if( StructKeyExists( fileOperationsCache, cacheKey ) ){
			_log( "AI: Using cached source file path" );
			return fileOperationsCache[ cacheKey ].path;
		}
		fileOperationsCache[ cacheKey ] = { path: filePath };
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
		var cacheKey = path;
		if( fileOperationsCache.KeyExists( cacheKey ) ){
			_log( "AI: Using cached existence test for resolution cache folder" );
			return true;
		}
		var pathExists = DirectoryExists( path );
		if( pathExists )
			cachePathExistence( path );
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

	private boolean function cachedFileExists( required string path ){
		if( !config.cacheFileOperations )
			return FileExists( path );
		if( fileOperationsCache.KeyExists( path ) ){
			_log( "AI: Using cached existence test for cached path" );
			return true;
		}
		var pathExists = FileExists( path );
		if( pathExists )
			cachePathExistence( path );
		return pathExists;
	}

	//This check is expensive: disabled by default, but use if images change frequently and you are not using deleteCachedCopies() when performing updates
	private boolean function fileHasBeenUpdated( required string sourceFilePath, required string cachedFilePath ){
		// get last modified of cached file
		var cacheDate = _GetFileInfo( cachedFilePath ).lastModified; 
		// get last modified of original
		var sourceDate = _GetFileInfo( sourceFilePath ).lastModified;
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
		throw( type: "AdaptiveImages.invalidFileExtension", message: "The file requested has an invalid file extension: '#requestedFileExtension#'." );
	}

	private void function _log( required string text, string file = config.logFilename ){
		if( config.writeLogs )
			WriteLog( file: "#file#", text: "#text#" );
	}

	private void function sendImage( required string filepath, required string mimeType, browserCacheSeconds = config.browserCacheSeconds ){
		cfheader( name: "Content-type", value: mimeType );
		if( IsNumeric( browserCacheSeconds ) )
			cfheader( name: "Cache-Control", value: "private,max-age=#browserCacheSeconds#" );
		var fileInfo = _GetFileInfo( filepath );
		cfheader( name: "Content-Length", value: fileInfo.size );
		cfcontent( file: filepath, type: mimeType );
		abort;
	}

	private void function deleteCookie(){
		cfcookie( name: "resolution", value: "deleted", expires: "now" ); //Change value to make testable
	}

	private struct function _GetFileInfo( required string path ){
		if( !isLucee )
			return GetFileInfo( arguments.path );
		var result = FileInfo( arguments.path );
		// support GetFileInfo().lastmodified
		result.lastmodified = result.dateLastModified;
		return result;
	}

}