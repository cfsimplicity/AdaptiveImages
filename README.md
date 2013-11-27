# Adaptive Images
The is an adapted ColdFusion port of Matt Wilcox's [Adaptive Images](http://adaptive-images.com/), a server-side solution to automatically create, cache, and deliver device-appropriate versions of your website’s content images.

## Acknowledgements
In addition to [Matt's code](https://github.com/MattWilcox/Adaptive-Images), I also took inspiration and code from [Raymond Camden's ColdFusion fork](https://github.com/cfjedimaster/Adaptive-Images)

### Differences
However, this is not a direct port of either project, placing more emphasis on performance through:

 - in-memory caching of file path and existence tests to reduce disk access;
 - assuming the source file existence check has been handled by the web server rewrite engine;
 - removal of some configuration options such as the `cache_path` - cached files are stored by convention in numbered folders in the same location as the source image;
 - checking that the bytesize of the resized file is no larger than the original (sometimes downscaling an image can actually increase its file size);

There are additional file and memory cache maintenance functions to ensure they don't become stale.

## Requirements
 - Adobe ColdFusion 9.0.1+ (Not yet tested on any other platforms)
 - Web server URL rewriting

## Usage

1) Create an instance of AdaptiveImages in the onApplicationStart() method of your Application.cfc

```
application.adaptiveImages  = New AdaptiveImages( resolutions=[ 320,480,1024 ] );
```

2) Create a ColdFusion template in your webroot to invoke the AdaptiveImages component and pass image requests to it.

***adaptiveImages.cfm***
```
<cfscript>
try{
	application.adaptiveImages().process( cgi.HTTP_X_ORIGINAL_URL );
}
catch( any exception ){
	abort;
}
</cfscript>
```

(Note: `cgi.HTTP_X_ORIGINAL_URL` is the variable made available in ColdFusion by IIS7. If using a different web server, it will have its own cgi scoped key name for the originally requested URL).

3) Add a rule to your web server's Rewrite Engine to intercept requests for image files and pass them to the CF template. Your rule should define which images you want AdaptiveImages to handle. Here's an example in IIS7 format:

```
<rule name="Adaptive Images" stopProcessing="true">
  <!-- Source image matching rule: this one applies AI to files in the /images/ folder only, no sub-folders -->
  <match url="images/[^\/]+\.(?:jpe?g|gif|png)$" />
  <action type="Rewrite" url="adaptiveImages.cfm" appendQueryString="false" />
  <!-- Test existence of source file here. Faster than using CF -->
  <conditions>
  	<add input="{REQUEST_FILENAME}" matchType="IsFile" />
  </conditions>
</rule>
```

4) Add the following javascript to the HTML `<head>` of all of your web pages to detect and store the client device's resolution/pixel density.
```
document.cookie='resolution='+Math.max(screen.width,screen.height)+("devicePixelRatio" in window ? ","+devicePixelRatio : ",1")+'; path=/';
```

##Configuration options
You can pass these arguments when instantiating AdaptiveImages.cfc:
 - `resolutions` *required*. An array of the device widths you wish to support, in pixels and in any order
 - `cacheFileOperations` boolean: default=true. Whether to cache source file paths and file existence tests to avoid unnecessary disk access
 - `checkForFileUpdates` boolean: default=false. Ensure updated source images are re-cached (requires disk access on every request)
 - `browserCacheSeconds` integer: default=2592000 (30 days). Number of seconds the BROWSER cache should last
 - `pixelDensityMultiplier` number between 1 and 3: default=1.5. By how much to multiply the resolution for "retina" displays as detected by the resolution cookie
 - `jpgQuality` number between 1 and 100: default=50. The quality of resized JPGs
 - `sharpen` boolean: default=true. Shrinking images can blur details. Perform a sharpen on re-scaled images?
 - `interpolation` string: defalt="highPerformance". Interpolation algorithm to use when scaling/resizing file (depending on whether performance or quality is paramount)
 - `writeLogs` boolean: default=false. Whether or not to log activity - don't use in production
 - `logFilename`: string: default="adaptive-images". If logging, the name of the file.

## Updating source files
For best performance don't turn on the `checkForFileUpdates` option. If you need to update or delete a source image, call the `deleteCachedCopies( fullImagePath )` method from your update/delete code passing in the full path of the image file.

## Housekeeping
Use the `cleanupCacheFolders( sourceImageFolder )` method periodically to remove any cached files where the source image no longer exists. Currently this function is not recursive, so needs to be applied separately to each parent source image folder containing cached image folders.

## Test Suite
Tests require [MXUnit 2.0](http://mxunit.org/)

## Legal
The original Adaptive Images by Matt Wilcox is licensed under a [Creative Commons Attribution 3.0 Unported License](http://creativecommons.org/licenses/by/3.0/)

This port is licensed under an MIT license

###The MIT License (MIT)

Copyright (c) 2013 Julian Halliwell

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
