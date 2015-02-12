<cfscript>
testPaths = [ "root.tests.tests" ];
testRunner = New testbox.system.testbox( testPaths );
WriteOutput( testRunner.run() );
</cfscript>