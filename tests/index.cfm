<cfscript>
request.testSuite = New mxunit.framework.TestSuite().testSuite();
request.testSuite.addAll( "tests" );
request.results = request.testSuite.run();
</cfscript>
<cfoutput>#request.results.getResultsOutput( "html" )#</cfoutput>  
