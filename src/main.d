import sicas.png;
import sicas.fonts;
import vibe.d;

import std.math			: floor;
import std.algorithm	: fill, sum, max;
import std.random		: Random, randomCover, unpredictableSeed, uniform;
import std.conv			: to;
import std.stdio		: stderr, writefln;
import std.getopt		: getopt;
import std.uuid			: UUID, randomUUID;

struct Captcha
{
	string	text;
	ubyte[]	image;
	SysTime expires;
}

struct Response
{
	this(in int status, in string reason)
	{
		this.status = status;
		this.success = status >= 200 && status < 300;
		this.reason = reason;
	}
	
	int		status;
	string	reason;
	bool	success;
}

int main(string[] args)
{
	enum	PROGRAM_VERSION		= "1.52";
	enum	PROGRAM_BUILD_YEAR	= "2015";
	
	ushort	captchaLength		= 6;			// Minimum (default) captcha string length
	string	fontName			= null;
	ushort	port				= 0x51CA;		// 20938
	ushort	imageHeight			= 32;			// Minimum (default) image width in pixels
	ushort	imageWidth			= 64;			// Minimum (default) image width in pixels
	ushort	timeout				= 120;			// Captcha timeout in seconds
	bool	corsEnabled			= false;		// Cross-origin resource sharing
	
	// Parse program arguments as options
	bool optHelp, optVersion;
	auto optParser = getopt(args,
		"h|height",		"captcha image height (default: 32)",			&imageHeight,
		"l|length",		"captcha string length (default: 6)",			&captchaLength,
		"p|port",		"sicas server port (default: 20938)",			&port,
		"w|width",		"captcha image width (default: 64)",			&imageWidth,
		"t|timeout",	"response timeout in seconds (default: 120)",	&timeout,
		"cors",			"enable cross-origin resource sharing (CORS)",	&corsEnabled,
		"help",			"display this help information and exit",		&optHelp,
		"version",		"display version information and exit",			&optVersion
	);
	
	// Remove default help option
	optParser.options = optParser.options[0 .. $ - 1];
	
	// Handle custom help output
	if(optHelp)
	{
		writefln("Usage: %s [OPTION]...", args[0]);
		writefln("Simple Image Captcha Server\n");
		
		size_t longestLength;
		
		foreach(opt; optParser.options)
			longestLength = max(longestLength, opt.optLong.length);
		
		foreach(opt; optParser.options)
			writefln("  %s %-*s %s", (opt.optShort ? opt.optShort ~ "," : "   "), longestLength, opt.optLong, opt.help);
			
		return 0;
	}
	
	// Handle version output
	if(optVersion)
	{
		writefln("sicas (Simple Image Captcha Server) v%s", PROGRAM_VERSION);
		writefln("Copyright (C) %s - Norwegian Polar Institute", PROGRAM_BUILD_YEAR);
		writefln("Licensed under the MIT license <http://opensource.org/licenses/MIT>");
		writefln("This is free software; you are free to change and redistribute it.");
		writefln("\nWritten by: Remi A. Solås (remi@npolar.no)");
		return 0;
	}
	
	Font* captchaFont;			// Pointer to sicas font in use
	Captcha[string] captchas;	// Map of captchas
	
	// Use specified font if set, otherwise fallback to default
	if(fontName)
	{
		if(!(fontName in fonts))
		{
			stderr.writefln("font does not exist: %s", fontName);
			return 1;
		}
		else captchaFont = &fonts[fontName];
	} else captchaFont = &fonts["default"];
	
	// Function called to generate new captcha image
	void routeGenerate(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Enable CORS support if required
		if(corsEnabled)
		{
			res.headers["Access-Control-Allow-Headers"] = "Authorization";
			res.headers["Access-Control-Allow-Origin"] = "*";
		}
		
		// Handle OPTIONS requests
		if(req.method == HTTPMethod.OPTIONS)
		{
			res.headers["Allow"] = "HEAD,GET,OPTIONS";
			res.writeVoidBody();
			return;
		}
		
		// Enforce GET or HEAD method
		enforceHTTP(req.method == HTTPMethod.GET || req.method == HTTPMethod.HEAD, HTTPStatus.methodNotAllowed, "Expected GET on path: /");
		
		ushort width	= imageWidth;
		ushort height	= imageHeight;
		ushort length	= captchaLength;
			
		// Override width from query
		if("width" in req.query)
			width = max(to!ushort(req.query["width"]), imageWidth);
		
		// Override height from query
		if("height" in req.query)
			height = max(to!ushort(req.query["height"]), imageHeight);
			
		// Override length for query
		if("length" in req.query)
			length = max(to!ushort(req.query["length"]), captchaLength);
		
		// Create a new PNG image of specified dimensions
		auto image = PNG(width, height);
			
		// Generate captcha image background
		foreach(y; 0 .. height)
			foreach(x; 0 .. width)
				image.image ~= cast(char[]) [ floor(255f / width * x), floor(255f / height * y), 255, floor(255f / (height + width) * (y + x)) ];
					
		// Generate random captcha string
		dchar[] randomString = new dchar[length];
		fill(randomString[], randomCover(to!(dchar[])(captchaFont.glyphs), Random(unpredictableSeed)));
		string captchaString = to!string(randomString);
		
		// Add captcha string to image
		uint x, y, pixelOffset, glyphOffset;
		uint offsetLeft = cast(uint) floor((width - (length * captchaFont.width)) / 2f);
		uint offsetTop = cast(uint) floor((height - captchaFont.height) / 2f);
			
		foreach(glyph; captchaString)
		{
			y = offsetTop + uniform(-5, 5);
			
			foreach(glyphLine; captchaFont.glyphRGBA(glyph))
			{
				x = offsetLeft + (glyphOffset * captchaFont.width);
				
				foreach(glyphPixel; glyphLine)
				{
					if((cast(uint[]) glyphPixel).sum != 0)
					{
						pixelOffset = (y * width * 4) + (x * 4);
						image.image[pixelOffset .. pixelOffset + 4] = glyphPixel;
					}
					
					++x;
				}
				++y;
			}
			
			++glyphOffset;
		}
		
		// Add some random noise to image
		for(x = 0; x < width; ++x)
		{
			for(y = 0; y < height; ++y)
			{
				if(uniform(0, 789) < 13)
				{
					pixelOffset = (y * width * 4) + (x * 4);
					auto pixel = image.image[pixelOffset .. pixelOffset + 4];
					image.image[pixelOffset .. pixelOffset + 4] = [ cast(char) uniform(0, 255), 0xFF ^ pixel[1], 0xFF ^ pixel[2], cast(char) uniform(0, 255) ];
				}
			}
		}
		
		// Generate captcha UUID and expire time
		string uuid = randomUUID().toString();
		auto expires = Clock.currTime + timeout.seconds;
			
		// Add captcha to cache and timeout for removal
		captchas[uuid] = Captcha(captchaString, cast(ubyte[]) image.data, expires);
		setTimer(timeout.seconds, { captchas.remove(uuid); });
		
		// Add response headers
		res.headers["Content-Location"] = "/image/" ~ uuid;
		res.headers["Content-Type"] = "application/json; charset=UTF-8";
		res.headers["Expires"] = toRFC822DateTimeString(expires);
		
		// Reply with no body if HEAD was requested
		if(req.method == HTTPMethod.HEAD)
		{
			res.writeVoidBody();
			return;
		}
		
		res.writeJsonBody([
			"uuid": uuid,
			"path": res.headers["Content-Location"],
			"expires": (expires).toUTC.toISOString
		], HTTPStatus.ok);
	}
	
	// Function called to retrieve captcha image from uuid (etag)
	void routeImage(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Enforce GET method
		enforceHTTP(req.method == HTTPMethod.GET, HTTPStatus.methodNotAllowed, "Expected GET on path: /image");
		
		// Captcha UUID string variable
		string uuid;
		
		// Make sure captcha UUID exists
		if(!((uuid = req.params["uuid"]) in captchas))
		{
			// Return 404 (Not Found) if the UUID does not exist
			res.writeJsonBody(Response(HTTPStatus.notFound, "Captcha image not found"), HTTPStatus.notFound);
			return;
		}
		
		// Add response headers
		res.headers["ETag"] = uuid;
		res.headers["Expires"] = toRFC822DateTimeString(captchas[uuid].expires);
		
		// Add captcha image to response body
		res.writeBody(captchas[uuid].image, "image/png");
	}
	
	// Function called to validate captcha string
	void routeValidate(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Captcha UUID and text variables
		string uuid, text;
		
		// Make sure UUID has been provided
		if(!("uuid" in req.params) || !req.params["uuid"].length)
		{
			// Return 400 (Bad Request) if no UUID was provided
			res.writeJsonBody(Response(HTTPStatus.badRequest, "Missing captcha UUID on path: /validate"), HTTPStatus.badRequest);
			return;
		}
		
		// Make sure captcha exists (has not timed out)
		if(!((uuid = req.params["uuid"]) in captchas))
		{
			// Return 404 (Not Found) if the UUID does not exist
			res.writeJsonBody(Response(HTTPStatus.notFound, "Captcha not found"), HTTPStatus.notFound);
			return;
		}
		
		// First try validating captcha using string query
		if("string" in req.query)
			text = req.query["string"];
		
		// ...otherwise validate captcha using POST
		else if(req.method != HTTPMethod.POST)
		{
			res.writeJsonBody(Response(HTTPStatus.methodNotAllowed, "Expected POST when not passing string as query"), HTTPStatus.methodNotAllowed);
			return;
		}
		
		// Enforce captcha input as sicas from form
		else if(!("sicas" in req.form))
		{
			res.writeJsonBody(Response(HTTPStatus.badRequest, "Missing captcha input"), HTTPStatus.badRequest);
			return;
		}
		else text = req.form["sicas"];
		
		// Validate captcha
		if(text != captchas[uuid].text)
		{
			// Return 403 (Forbidden) if the captcha is invalid
			res.writeJsonBody(Response(HTTPStatus.forbidden, "Invalid captcha"), HTTPStatus.forbidden);
			return;
		}
		
		// Return 200 (Ok) if the captcha validation succeeded
		res.writeJsonBody(Response(HTTPStatus.ok, "Success"), HTTPStatus.ok);
		captchas.remove(uuid);
	}
	
	// Create URL routes for captcha generation/validation
	auto router = new URLRouter;
	router
	.any("/", &routeGenerate)
	.any("/image/:uuid", &routeImage)
	.any("/validate/:uuid", &routeValidate);
	
	// Set specified lister port, and enable worker-thread distribution
	auto httpSettings = new HTTPServerSettings;
	httpSettings.options |= HTTPServerOption.distribute;
	httpSettings.port = port;
	
	// TODO: Add HTTPS support (httpSettings.tlsContext)
	
	// Start HTTP listening, and run event loop
	listenHTTP(httpSettings, router);
	return runEventLoop();
}
