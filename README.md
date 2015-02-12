# Adaptive Images
This is a ColdFusion version of Matt Wilcox's [Adaptive Images](http://adaptive-images.com/), a server-side solution to automatically create, cache, and deliver device-appropriate versions of your website’s images.

If your site's design is "responsive", so that images are not given a fixed width or height but scaled to the width of their container, you can save bandwidth and speed up client load times by using AdaptiveImages to ensure end users do not have to download images intended for the widest screens. Instead, smaller versions will be created and served as necessary, according to the detected resolution of the device.

[More background](http://cfsimplicity.com/73/the-simplicity-of-adaptive-images)

## Acknowledgements
In addition to [Matt's PHP code](https://github.com/MattWilcox/Adaptive-Images), I also took inspiration and code from [Raymond Camden's ColdFusion fork](https://github.com/cfjedimaster/Adaptive-Images)

### Differences
However, this is not a direct port of either project. It places more emphasis on performance through:

 - in-memory caching of file path and existence tests to minimise disk access;
 - assuming the source file existence check has been handled by the web server rewrite engine;
 - removal of some configuration options such as the `cache_path` - cached files are stored by convention in folders named by resolution width in the same location as the source image;
 - checking that the bytesize of the resized file is no larger than the original (sometimes downscaling an image can actually increase its file size);

There are additional file and memory cache maintenance functions to ensure they don't become stale.

## Requirements
 - Adobe ColdFusion 9.0.1 (Likely to work on later versions but not tested)
 - Railo 4.2 or Lucee Server 4.5
 - Web server URL rewriting

## Usage

1) Create an instance of AdaptiveImages in the onApplicationStart() method of your Application.cfc, specifying the resolutions you want to support (use your web analytics to determine the most common device widths).

```
application.adaptiveImages  = New adaptiveImages( resolutions=[ 320,480,768,1024,1400,1680 ] );
```

2) Create a ColdFusion template in your webroot to invoke the AdaptiveImages component and pass image requests to it.

***adaptiveImages.cfm***
```
<cfscript>
try{
	application.adaptiveImages.process( cgi.HTTP_X_ORIGINAL_URL );
}
catch( any exception ){
	abort;
}
</cfscript>
```

(Note: `cgi.HTTP_X_ORIGINAL_URL` is the variable made available in ColdFusion by IIS7. If using a different web server, it will have its own cgi scoped key name for the originally requested URL).

3) Add a rule to your web server's Rewrite Engine to intercept requests for image files and pass them to the CF template. Your rule should define which images you want AdaptiveImages to handle. Here's an example in **IIS7** format:

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
<script>
document.cookie='resolution='+Math.max(screen.width,screen.height)+("devicePixelRatio" in window ? ","+devicePixelRatio : ",1")+'; path=/';
</script>
```

##Configuration options
You can pass these arguments when instantiating AdaptiveImages.cfc:
 - `resolutions` *required*. An array of the device widths you wish to support, in pixels and in any order.
 - `cacheFileOperations` boolean: default=true. Whether to cache source file paths and file existence tests to avoid unnecessary disk access. You will normally want to keep this enabled unless your source files change very frequently and you are not using the cache maintenance functions, or you are memory-constrained and have a lot of files (but note that only the *paths* are stored, not the images themselves).
 - `checkForFileUpdates` boolean: default=false. Ensure updated source images are re-cached (requires disk access on every request).
 - `browserCacheSeconds` integer: default=2592000 (30 days). Number of seconds the *browser* cache should last.
 - `pixelDensityMultiplier` number between 1 and 3: default=1.5. By how much to multiply the resolution for "retina" displays as detected by the resolution cookie.
 - `jpgQuality` number between 1 and 100: default=50. The quality of resized JPGs.
 - `sharpen` boolean: default=true. Shrinking images can blur details. Perform a sharpen on re-scaled images?
 - `interpolation` string: default="highPerformance". Interpolation algorithm to use when scaling/resizing file (depending on whether performance or quality is paramount).
 - `writeLogs` boolean: default=false. Whether or not to log activity - don't use in production.
 - `logFilename`: string: default="adaptive-images". If logging, the name of the file.

## Updating source files
For best performance keep the `checkForFileUpdates` option disabled. If you need to update or delete a source image, call the `deleteCachedCopies( fullImagePath )` method from your update/delete code passing in the full path of the image file.

## Housekeeping
Use the `cleanupCacheFolders( sourceImageFolder )` method periodically to remove any cached files where the source image no longer exists. Currently this function is not recursive, so needs to be applied separately to each parent source image folder containing cached image folders.

## Test Suite
Tests require [TestBox 2.1](https://github.com/Ortus-Solutions/TestBox). You will need to create an application mapping for `/testbox`.

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
