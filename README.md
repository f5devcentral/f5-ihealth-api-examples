F5 Networks iHealth API Example scripts
=======================================

This is a collection of example scripts that use the Bash shell to show examples of how to utilize F5's iHealth Webservice APIs.

These shell scripts provide non-comprehensive coverage of the usage of the iHealth APIs, and are not meant to be complete solutions, but instead serve as examples for people wishing to start with working examples, or as examples for people wishing to implement their iHealth API usage in a different language.

Dependencies
------------

The scripts, since they are in Bash, depend on some external programs to deal with the structured output from the APIs and perform the HTTP transactions:

- [jq](https://stedolan.github.io/jq/)
- [xmlstarlet](http://xmlstar.sourceforge.net/)
- [curl](https://curl.haxx.se/)

These three things *should* be pretty widely available in whatever environment you are working in.

References
----------

- [F5](https://f5.com)
- [F5 DevCentral](https://devcentral.f5.com)
- [iHealth API](https://ihealth-api.f5.com/qkview-analyzer/api/docs/index.html)
