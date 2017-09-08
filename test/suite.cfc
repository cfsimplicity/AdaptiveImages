	component extends="testbox.system.BaseSpec"{
	/* 
		Requirements for running test suite:
		TestBox 2.1+ https://github.com/Ortus-Solutions/TestBox
		Application mapping for /testbox
		Web server directory (virtual or real) for /adaptiveImages
	*/

	function beforeAll(){
		variables.imageFolderUrl = "/root/test/images/";
		variables.imageFolderPath = forwardSlashes( ExpandPath( imageFolderUrl ) );
		variables.imageFilename = "test.jpg";
		variables.sourceImageUrl = imageFolderUrl & imageFilename;
		variables.sourceImagePath = forwardSlashes( ExpandPath( sourceImageUrl ) );
		variables.sourceImageUrlCacheKey = REReplace( sourceImageUrl, "^/", "" );
	}

	function afterAll(){
		deleteResolutionCookie();
	}

	function run( testResults, testBox ){

		describe( "adaptiveImages test suite",function() {

			beforeEach( function( currentSpec ) {
				variables.ai = New root.adaptiveImages( [ "480","320" ] );
				prepareMock( ai );
			});

			describe( "on init",function(){

				it( "throws an exception if no resolutions are defined", function() {
					expect( function(){
						ai = New root.adaptiveImages( [] );
					}).toThrow( type: "AdaptiveImages.invalidConfiguration" );
				} );

				it( "throws an exception if browserCacheSeconds is not an integer", function() {
					expect( function(){
						ai = New root.adaptiveImages( resolutions: [ "480" ], browserCacheSeconds: 5.1 );
					}).toThrow( type: "AdaptiveImages.invalidConfiguration" );
				} );

				it( "throws an exception if pixelDensityMultiplier is invalid", function() {
					expect( function(){
						ai = New root.adaptiveImages( resolutions: [ "480" ], pixelDensityMultiplier: 0 );
					}).toThrow( type: "AdaptiveImages.invalidConfiguration" );
				} );

				it( "throws an exception if jpegQuality is invalid", function() {
					expect( function(){
						ai = New root.adaptiveImages( resolutions: [ "480" ], jpgQuality: 0 );
					}).toThrow( type: "AdaptiveImages.invalidConfiguration" );
				} );

				it( "sorts resolutions smallest first", function(){
					var config = ai.getConfig();
					expect( config.smallestResolution ).toBeLT( config.largestResolution );
				});

			});

			describe( "getSourceFilePath", function(){

				beforeEach( function(){
					makePublic( ai, "getSourceFilePath" );
				});

				it( "returns the path from a valid source image url", function() {
					expect( ai.getSourceFilePath( sourceImageUrl ) ).toBe( imageFolderPath & "test.jpg" );
				} );

				it( "caches path by default", function() {
					var cache = ai.getFileOperationsCache();
					var sourceFilePath = ai.getSourceFilePath( sourceImageUrl );
					expect( cache ).toHaveKey( sourceImageUrlCacheKey );
					expect( cache[ sourceImageUrlCacheKey ].path ).toBe( imageFolderPath & "test.jpg" );
				} );

			});

			it( "handles gif, jpeg and png", function() {
				makePublic( ai, "mimeType" );
				expect( ai.mimeType( "gif" ) ).toBe( "image/gif" );
				expect( ai.mimeType( "jpe" ) ).toBe( "image/jpeg" );
				expect( ai.mimeType( "jpg" ) ).toBe( "image/jpeg" );
				expect( ai.mimeType( "png" ) ).toBe( "image/png" );
			} );

			it( "throws an exception if file extension is invalid", function() {
				makePublic( ai, "mimeType" );
				expect( function(){
					ai.mimeType( ".doc" );
				}).toThrow( type: "AdaptiveImages.invalidFileExtension" );
			} );

			it( "finds 'mobile' anywhere in user agent string", function(){
				makePublic( ai, "isMobile" );
				expect( ai.isMobile( "Mozilla/5.0 (Windows NT 6.1; rv:23.0) Gecko/20100101 Firefox/23.0 " ) ).toBeFalse();
				expect( ai.isMobile( "Mozilla/5.0 (compatible; MSIE 9.0; Windows Phone OS 7.5; Trident/5.0; IEMobile/9.0)" ) ).toBeTrue();
			});

			it( "can set the resolution cookie", function() {
				setResolutionCookie( "480,0" );
				expect( cookie ).toHaveKey( "resolution" );
			} );
			
			it( "can validate the resolution cookie", function() {
				makePublic( ai, "cookieIsValid" );
				var validValue = "480,0";
				var invalidValue = "abc";
				setResolutionCookie( validValue );
				expect( ai.cookieIsValid() ).toBeTrue();
				setResolutionCookie( invalidValue );
				expect( ai.cookieIsValid() ).toBeFalse();
			} );

			it( "can delete the resolution cookie", function() {
				makePublic( ai, "deleteCookie" );
				setResolutionCookie( "480,0" );
				ai.deleteCookie();
				expect( cookie.resolution ).toBe( "deleted" );// Can't test deletion on same request but deleteCookie will also change value: test that.
			} );

			it( "defaults to the smallest value for mobile", function() {
				makePublic( ai, "defaultResolution" );
				ai.$( method: "isMobile", returns: true );
				var config = ai.getConfig();
				expect( ai.defaultResolution() ).toBe( config.smallestResolution );
			} );

			it( "defaults to the largest value for non-mobile", function() {
				makePublic( ai, "defaultResolution" );
				ai.$( method: "isMobile", returns: false );
				var config = ai.getConfig();
				expect( ai.defaultResolution() ).toBe( config.largestResolution );
			} );

			it( "sets resolution as detected value if result is higher than largest defined", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ 320, 480 ], pixelDensityMultiplier: 1.5 );
				makePublic( ai, "resolution" );
				setResolutionCookie( "500,1" );//non-retina
				expect( ai.resolution() ).toBe( 500 );// client width is bigger than largest defined
			} );

			it( "sets resolution as next largest if detected value is lower than largest defined", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ 320, 480, 1024 ], pixelDensityMultiplier: 1.5 );
				makePublic( ai, "resolution" );
				setResolutionCookie( "300,1" );
				expect( ai.resolution() ).toBe( 320 );// retina resolution is 450. Expect next highest defined
			} );

			it( "sets resolution as computed value if retina detected and result is higher than largest defined", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ 320, 480 ], pixelDensityMultiplier: 1.5 );
				makePublic( ai, "resolution" );
				setResolutionCookie( "500,2" );// set as retina display so multiplier is applied
				expect( ai.resolution() ).toBe( 750 );//multiplier is 1.5 so 500x1.5. Bigger than largest defined
			} );

			it( "sets resolution as next largest if retina detected and computed value is lower than largest defined", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ 320, 480, 1024 ], pixelDensityMultiplier: 1.5 );
				makePublic( ai, "resolution" );
				setResolutionCookie( "300,2" );// set as retina display so multiplier is applied
				expect( ai.resolution() ).toBe( 480 );// retina resolution is 450. Expect next highest defined
			} );

			it( "returns the source image if the detected resolution exceeds the largest defined", function() {
				ai.$property( propertyName: "sendImage", mock: sendImage );
				setResolutionCookie( "500,1" );
				expect( ai.process( sourceImageUrl ) ).toBe( sourceImagePath );
			} );

			it( "detects and caches cached file existence", function() {
				makePublic( ai, "cachedFileExists" );
				var cacheFilePath = createCachedFile( 300, ai );
				expect( ai.cachedFileExists( cacheFilePath ) ).toBeTrue();
				var cache = ai.getFileOperationsCache();
				expect( cache ).toHaveKey( cacheFilePath );
				deleteFolder( GetDirectoryFromPath( cacheFilePath ) );
			} );

			it( "sends cached image if it exists", function() {
				ai.$property( propertyName: "sendImage", mock: sendImage );
				ai[ "setFileOperationsCacheValue" ] = setFileOperationsCacheValue; // add this temporary method
				var cacheFilePath = createCachedFile( 320, ai );
				ai.setFileOperationsCacheValue( cacheFilePath, true );
				setResolutionCookie( "300,1" );
				expect( ai.process( sourceImageUrl ) ).toBe( cacheFilePath );
				deleteFolder( GetDirectoryFromPath( cacheFilePath ) );
			} );

			it( "sends source image if resolution exceeds source width", function() {
				ai.$property( propertyName: "sendImage", mock: sendImage );
				// test image is 600px wide
				setResolutionCookie( "700,1" );
				expect( ai.process( sourceImageUrl ) ).toBe( sourceImagePath );
			} );

			it( "generateImage resizes to specified width", function() {
				var sourceImage = ImageRead( sourceImagePath );
				makePublic( ai, "generateImage" );
				var resizedImage = ai.generateImage( sourceImage, 320 );
				expect( resizedImage.width ).toBe( 320 );
			} );

			it( "creates cache folder and caches path", function() {
				makePublic( ai, "ensureCacheFolderExists" );
				var cacheFolderPath = imageFolderPath & 320 & "/";
				deleteFolder( cacheFolderPath );//ensure it doesn't exist.
				ai.ensureCacheFolderExists( cacheFolderPath );
				expect( DirectoryExists( cacheFolderPath ) ).toBeTrue();
				var cache = ai.getFileOperationsCache();
				expect( cache ).toHaveKey( cacheFolderPath );
				deleteFolder( cacheFolderPath );
			} );

			it( "creates cache folder and caches path using optional cache folder name", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ "480","320" ], cacheFolderName: "ai-cache" );
				makePublic( ai, "ensureCacheFolderExists" );
				var cacheFolderPath = imageFolderPath & "ai-cache/" & 320 & "/";
				deleteFolder( cacheFolderPath );//ensure it doesn't exist.
				ai.ensureCacheFolderExists( cacheFolderPath );
				expect( DirectoryExists( cacheFolderPath ) ).toBeTrue();
				var cache = ai.getFileOperationsCache();
				expect( cache ).toHaveKey( cacheFolderPath );
				deleteFolder( imageFolderPath & "ai-cache/" );
			} );

			it( "caches a copy of the source if the resized image is larger in bytes", function() {
				makePublic( ai, "checkCachedImageIsNotLargerThanSource" );
				var largerTestImagePath = imageFolderPath & "largerFileSizeThanSource.jpg";
				var cacheFolderPath = imageFolderPath & 320 & "/";
				deleteFolder( cacheFolderPath );//ensure it doesn't exist.
				DirectoryCreate( cacheFolderPath );
				cachedFilePath = cacheFolderPath & "test.jpg";
				FileCopy( largerTestImagePath, cachedFilePath );
				ai.checkCachedImageIsNotLargerThanSource( cachedFilePath, sourceImagePath );
				var expected = GetFileInfo( sourceImagePath ).size;
				var actual = GetFileInfo( cachedFilePath ).size;
				expect( actual ).toBe( expected );
				deleteFolder( cacheFolderPath );
			} );

			it( "caches and sends an image sized to the detected resolution if not already in cache", function() {
				ai.$property( propertyName: "sendImage", mock: sendImage );
				var cacheFolderPath = imageFolderPath & 320 & "/";
				var cacheFilePath = cacheFolderPath & "test.jpg";
				deleteFolder( cacheFolderPath );//ensure it doesn't exist.
				setResolutionCookie( "300,1" );
				expect( ai.process( sourceImageUrl ) ).toBe( cacheFilePath );
				deleteFolder( cacheFolderPath );
			} );

			it( "caches and sends an image sized to the detected resolution if not already in cache, using optional cache folder name", function() {
				variables.ai = New root.adaptiveImages( resolutions: [ "480","320" ], cacheFolderName: "ai-cache" );
				prepareMock( ai );
				ai.$property( propertyName: "sendImage", mock: sendImage );
				var cacheFolderPath = imageFolderPath & "ai-cache/" & 320 & "/";
				var cacheFilePath = cacheFolderPath & "test.jpg";
				deleteFolder( cacheFolderPath );//ensure it doesn't exist.
				setResolutionCookie( "300,1" );
				expect( ai.process( sourceImageUrl ) ).toBe( cacheFilePath );
				deleteFolder( imageFolderPath & "ai-cache/" );
			} );

			describe( "cleanupCacheFolders", function(){

				it( "deletes a cached image where the source no longer exists", function() {
					var cacheFilePath = createCachedFile( 320, ai, "nonexistantsource.jpg" );
					expect( FileExists( cacheFilePath ) ).toBeTrue();
					ai.cleanupCacheFolders( imageFolderUrl );
					expect( FileExists( cacheFilePath ) ).toBeFalse();
					// deletes empty resolution cache folders
					expect( DirectoryExists( GetDirectoryFromPath( cacheFilePath ) ) ).toBeFalse();
				} );

				it( "deletes a cached image where the source no longer exists using optional cache folder name", function() {
					variables.ai = New root.adaptiveImages( resolutions: [ "480","320" ], cacheFolderName: "ai-cache" );
					var cacheFilePath = createCachedFile( 320, ai, "nonexistantsource.jpg" );
					expect( FileExists( cacheFilePath ) ).toBeTrue();
					ai.cleanupCacheFolders( imageFolderUrl );
					expect( FileExists( cacheFilePath ) ).toBeFalse();
					// deletes empty resolution cache folders
					expect( DirectoryExists( GetDirectoryFromPath( cacheFilePath ) ) ).toBeFalse();
					deleteFolder( imageFolderPath & "ai-cache/" );
				} );

			});

			describe( "deleteCachedCopies", function() {
				
				it( "deletes cached resolution images for a given image", function() {
					var cacheFilePath1 = createCachedFile( 320, ai );
					var cacheFilePath2 = createCachedFile( 480, ai );
					expect( FileExists( cacheFilePath1 ) ).toBeTrue();
					expect( FileExists( cacheFilePath2 ) ).toBeTrue();
					ai.deleteCachedCopies( sourceImagePath );
					expect( FileExists( cacheFilePath1 ) ).toBeFalse();
					expect( FileExists( cacheFilePath2 ) ).toBeFalse();
					ai.cleanupCacheFolders( imageFolderPath );
				} );

				it( "deletes cached resolution images for a given image using optional cache folder name", function() {
					variables.ai = New root.adaptiveImages( resolutions: [ "480","320" ], cacheFolderName: "ai-cache" );
					var cacheFilePath1 = createCachedFile( 320, ai );
					var cacheFilePath2 = createCachedFile( 480, ai );
					expect( FileExists( cacheFilePath1 ) ).toBeTrue();
					expect( FileExists( cacheFilePath2 ) ).toBeTrue();
					ai.deleteCachedCopies( sourceImagePath );
					expect( FileExists( cacheFilePath1 ) ).toBeFalse();
					expect( FileExists( cacheFilePath2 ) ).toBeFalse();
					ai.cleanupCacheFolders( imageFolderPath );
					deleteFolder( imageFolderPath & "ai-cache/" );
				} );

			} );

		});

	}

	/* Mock */
	
	void function setFileOperationsCacheValue( required key, required value ){
		fileOperationsCache[ key ] = value;
	}

	string function sendImage( required string filepath ){
		//can't test actual sending, so just return the selected image path
		return filepath;
	}

	/* Helpers */
	string function forwardSlashes( required string path ){
		return path.Replace( "\", "/", "ALL" );
	}

	string function createCachedFile( required numeric resolution, required ai, filename = imageFilename  ){
		makePublic( ai, "resolutionFolderName" );
		var filePath = imageFolderPath & ai.resolutionFolderName( resolution ) & "/" & filename;
		createFile( filePath );
		return filePath;
	}

	void function createFile( path ){
		var folderPath = GetDirectoryFromPath( path );
		if( !DirectoryExists( folderPath ) )
			DirectoryCreate( folderPath );
		if( !FileExists( path ) )
			FileWrite( path, "test" );
	}

	void function deleteFolder( path ){
		if( DirectoryExists( path ) )
			DirectoryDelete( path, true );
	}

	void function setResolutionCookie( required string value ){
		cfcookie( name="resolution", value="#value#" );
	}

	void function deleteResolutionCookie(){
		cfcookie( name="resolution", value="deleted", expires="now" );
	}

}