import sicas.png;
import sicas.fonts;
import vibe.d;

import std.math			: floor;
import std.algorithm	: fill, sum;
import std.random		: Random, randomCover, unpredictableSeed, uniform;
import std.conv			: to;
import std.stdio		: stderr, writefln;
import std.getopt		: getopt;
import std.uuid			: UUID, randomUUID;
import std.digest.md	: md5Of, toHexString;
import std.regex		: matchFirst;

int main(string[] args)
{
	ushort	captchaLength		= 6;
	string	fontName			= null;
	string	path				= "/captcha";
	ushort	port				= 0x51CA;		// 20938
	ushort	imageHeight			= 32;
	ushort	imageWidth			= 64;
	ushort	timeout				= 120;			// Captcha timeout in seconds
	
	getopt(args,
		"h|image-height",	"captcha image height (default: 32)",			&imageHeight,
		"l|captcha-length",	"captcha string length (default: 6)",			&captchaLength,
		"path",				"HTTP request path (default: /captcha)",		&path,
		"p|port",			"sicas server port (default: 20938)",			&port,
		"w|image-width",	"captcha image width (default: 64)",			&imageWidth,
		"t|timeout",		"response timeout in seconds (default: 120)",	&timeout
	);
	
	Font* captchaFont;
	string[string] captchas;	// UUID-map of captcha strings
	
	if(fontName)
	{
		if(!(fontName in fonts))
		{
			stderr.writefln("font does not exist: %s", fontName);
			return 1;
		}
		else captchaFont = &fonts[fontName];
	} else captchaFont = &fonts["default"];
	
	void requestHandler(HTTPServerRequest req, HTTPServerResponse res)
	{
		if(req.path == path)
		{
			// Get new captcha image
			if(req.method == HTTPMethod.GET)
			{
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
				
				// Generate base64-encoded cookie key and captcha UUID
				string cookieKey = "sicas-" ~ toHexString(md5Of(randomUUID().toString())).idup;
				string uuid = randomUUID().toString();
				
				// Add captcha to cache and timeout for removal
				captchas[uuid] = captchaString;
				setTimer((timeout).seconds, { captchas.remove(uuid); });
				
				// Add cookie with UUID and expire time
				res.setCookie(cookieKey, uuid);
				res.cookies[cookieKey].maxAge = timeout;
				
				// Add captcha image to response body
				res.writeBody(cast(ubyte[]) image.data, "image/png");
			}
			
			// Verify captcha string
			else if(req.method == HTTPMethod.POST)
			{
				if("sicas" in req.form)
				{
					string captcha = req.form["sicas"];
					string uuid;
					
					foreach(cookie; req.cookies)
					{
						auto match = matchFirst(cookie.name, "^sicas-[A-F0-9]{32}$");
						
						if(!match.empty && ((uuid = cookie.value) in captchas))
						{
							if(captchas[uuid] == captcha)
							{
								res.writeBody("Success!", "text/plain");
								res.statusCode = 200;
								return;
							}
						}
					}
					
					if(uuid)
					{
						// Return 403 (Forbidden) if the captcha validation failed
						res.writeBody("Invalid captcha", "text/plain");
						res.statusCode = 403;
					}
					else
					{
						// Return 410 (Gone) if the captcha doesn't exist (has timed-out)
						res.writeBody("Captcha timeout", "text/plain");
						res.statusCode = 410;
					}
				}
				else
				{
					// Return 400 (Bad Request) if sicas was not found as a form POST element
					res.writeBody("Missing captcha", "text/plain");
					res.statusCode = 400;
				}
			}
		}
	}
	
	auto httpSettings = new HTTPServerSettings;
	httpSettings.port = port;
	
	listenHTTP(httpSettings, &requestHandler);
	return runEventLoop();
}
