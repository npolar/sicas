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
import std.digest.sha	: sha1Of, toHexString;
import std.regex		: matchFirst;

int main(string[] args)
{
	enum	PROGRAM_VERSION		= "1.0";
	enum	PROGRAM_BUILD_YEAR	= "2015";
	
	ushort	captchaLength		= 6;			// Minimum (default) captcha string length
	string	fontName			= null;
	ushort	port				= 0x51CA;		// 20938
	ushort	imageHeight			= 32;			// Minimum (default) image width in pixels
	ushort	imageWidth			= 64;			// Minimum (default) image width in pixels
	ushort	timeout				= 120;			// Captcha timeout in seconds
	
	// Parse program arguments as options
	bool optHelp, optVersion;
	auto optParser = getopt(args,
		"h|height",		"captcha image height (default: 32)",			&imageHeight,
		"l|length",		"captcha string length (default: 6)",			&captchaLength,
		"p|port",		"sicas server port (default: 20938)",			&port,
		"w|width",		"captcha image width (default: 64)",			&imageWidth,
		"t|timeout",	"response timeout in seconds (default: 120)",	&timeout,
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
	string[string] captchas;	// UUID-map of captcha strings
	
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
	void routeCaptcha(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Enforce GET method
		enforceHTTP(req.method == HTTPMethod.GET, HTTPStatus.methodNotAllowed, "Expected method GET on path: /captcha");
		
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
		
		// Generate captcha UUID, and cookie key
		string uuid = randomUUID().toString();
		string cookieKey = "sicas-" ~ toHexString(sha1Of(uuid ~ captchaString)).idup;
			
		// Add captcha to cache and timeout for removal
		captchas[uuid] = captchaString;
		setTimer((timeout).seconds, { captchas.remove(uuid); });
		
		// Add cookie with UUID and expire time
		res.setCookie(cookieKey, uuid);
		res.cookies[cookieKey].maxAge = timeout;
		
		// Add captcha image to response body
		res.writeBody(cast(ubyte[]) image.data, "image/png");
	}
	
	// Function called to validate captcha string
	void routeValidate(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Enforce POST method
		enforceHTTP(req.method == HTTPMethod.POST, HTTPStatus.methodNotAllowed, "Expected method POST on path: /validate");
		
		// Enforce captcha input as sicas from form
		enforceHTTP("sicas" in req.form, HTTPStatus.badRequest, "Missing captcha");
		
		string captchaString = req.form["sicas"], uuid;
		
		// Read UUID from cookie
		foreach(cookie; req.cookies)
		{
			auto match = matchFirst(cookie.name, "^sicas-([A-F0-9]{40})$");
			
			if(!match.empty && match[1] == toHexString(sha1Of(cookie.value ~ captchaString)))
			{
				uuid = cookie.value;
				break;
			}
		}
		
		if(uuid)
		{
			if((uuid in captchas) && (captchas[uuid] == captchaString))
			{
				// Return 200 (Ok) if the captcha validation succeeded
				res.writeBody("Success", "text/plain");
				res.statusCode = HTTPStatus.ok;
				captchas.remove(uuid);
			}
			else
			{
				// Return 410 (Gone) if the captcha has timed-out
				res.writeBody("Captcha timeout", "text/plain");
				res.statusCode = HTTPStatus.gone;
			}
			
			return;
		}
		
		// Return 403 (Forbidden) if the captcha validation failed
		res.writeBody("Invalid captcha", "text/plain");
		res.statusCode = HTTPStatus.forbidden;
		return;
	}
	
	// Create URL routes for captcha generation/validation
	auto router = new URLRouter;
	router
	.get("/captcha", &routeCaptcha)
	.post("/validate", &routeValidate);
	
	// Set specified lister port, and enable worker-thread distribution
	auto httpSettings = new HTTPServerSettings;
	httpSettings.options |= HTTPServerOption.distribute;
	httpSettings.port = port;
	
	// Start HTTP listening, and run event loop
	listenHTTP(httpSettings, router);
	return runEventLoop();
}
