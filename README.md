# Geocoding with SQL-Server

## Introduction
This article touches on a couple of issues related to geo-coding, in particular:  
Converting ESRI shape file to XML
*   Parsing address
*   Geo-coding address

All of the geo-coding is implemented as a SQL-Server function, and as such offers performance gains impossible to achieve by using other methods such as web-services or COM interface with mapping software (aka MapPoint).

## Background
My first experimentation with geo-coding probably goes 3 years back. Initially using some of the more widely available services such as Google or Yahoo web-service did do the job. At some point however, I started to hit the wall with this implementation. Namely there were 2 restrictions I had to deal with:
*   Sending address over the public web was not acceptable for some of the projects I was working on.
*   Every now and then I had to geo-code hundreds of thousands of records of legacy data.

Researching the web, I found wonderful John Sample's article (http://www.johnsample.com/articles/GeocodeWithSqlServer.aspx). His research really helped. Apparently everything you need is right there, along with gobs of free data - US Census Bureau Tiger/Line data that covers latitude/longitude of every city block of every county in US. Once you have a simple text file, you just load it into the database and then using interpolation techniques you can fairly easily find latitude/longitude of every address in US.  
That was working for me for a couple of years. Then I started to discover problems that I primarily blame on the housing boom of 2005-2007 :-). See, during this time there was apparently quite a bit of new construction and I started to notice a lot of new addresses that didn't exist in the Tiger/Line file I got when I started. No worries, I thought, I just will get a latest Tiger/Line file and will be on my way. Well, guess what, US Census Bureau doesn't provide text Tiger/Line file. Now they provide only ESRI binary shape files - and that threw a monkey wrench into my plans - I really needed some way to get the latest geo data in text format so I can load it into my SQL-server.  
The rest of the article describes 3 parts of this project:  
*   Conversion of ESRI shape files into the XML
*   Loading XML data into SQL-server
*   SQL-server function to parse US addresses and geocode them

## Tiger Files
US Census Bureau provides Topologically Integrated Geographic Encoding and Referencing system - TIGER - data. This is county-by-county geo information of every district, block, monument - pretty much anything that deserves any attention. In particular, I was interested in "All Lines" files that can be downloaded on county-by-county basis (Go to http://www2.census.gov/cgi-bin/shapefiles2009/national-files) navigate to your state and then county and download "All Lines" file). Inside this file, for each city block within the county you can find information such as address range, street name, zip code, and of course latitude/longitude for the start and the end of the street block. Initially this information was provided as an ASCII file downloads but since 2006, this information is available only as ESRI shape file.

## ESRI Shape Files / XML Conversion
ESRI seems to have become a de-facto standard of spatial data storage and presentation. At least their files and their file support become more and more widely available.  
It is probably worth it to provide 25,000 feet overview of the shape files. Shape file is actually a set that contains at least 4 files:  
*   SHP - shape files that contains actual shapes - a list of data structures with primarily an object type and list of points for each object
*   SHX - shape index file that tell where each object in the file is located
*   DBF - an old fashioned DBase database file that contains additional attributes for each shape/object. In case of Tiger/Line, this would contain street name, zip code, ... But it also can contain other generic information.
*   PRJ - file information, such as type of encoding/projection used in the file.

The fact that ESRI is a de-facto leader didn't make my job much easier though - still took a while to get ESRI shape files converted into text format. Eventually instead of trying to find a utility that would do it for me, I started to look for libraries that I can use to do the job.  
Even though I really wanted to find C# code to get the job done, eventually I settled on Shapefile C Library - [http://shapelib.maptools.org/](http://shapelib.maptools.org/) that was the simplest thing with no dependencies. They also had plenty of samples how to get it to work, so it made my job fairly easy - open DBF and SHP files and for each object in there, just dump the corresponding XML node.

## Object Types
As far as geo-coding, I was only interested in poly-lines. And for those, for simplicity sake, I was only interested in straight interpolation, so even for polylines I was interested in starting and ending points. So if your county has really long blocks with really curvy streets, you might want to look into making this process a little more precise. So in order to cut file size, when I export objects to XML file, whenever I have a poly line object, I will only export starting and ending position.  
For some other projects I was involved in, I needed to export polygons. For those I'm exporting all the points - so when you look in the code, don't be surprised.

## State-plane Coordinate Conversion
This portion of SHP file conversion is not used for address geo-coding. However for some other projects I was involved in, I had to deal with shape files encoded in state-plane coordinate system - so called Lambert Conformal Conic projection. At the risk of being laughed at by the geo-specialists, the simple description of this coordinate system the way I understood it is as follows - in order to increase precision of the mapping process for separate small areas, one of the type of geo-coding is to select a center of the area and then provide coordinates not in latitude/longitude, but instead in something like feet to the north/west - (like a pirate map - from the old tree 20 paces to the north and 3 paces to the east). Sounds silly but it's seems to be quite widespread. At least I had to deal with it so I had to build a module that would transparently check shape file projection system and convert it on the fly to latitude/longitude.  
For the basis of conversion, I chose the code published by Montana State Library and made it a little more generic, in particular add the code to get the projection information from the shape's file PRJ file.

## XML File Format
The XML file I chose to create is far from being generic or extensible and may not quite satisfy all you needs, but it did get the job done for me:  

```
<layer>
<shp property='value' property='value' property='value' xFrom='lon' yFrom='lat' xTo='lon' yTo='lat'>
      lon lat lon lat ...
</shp>
</layer>
```

In this file
node is repeated for each shape object. Each column/attribute in the DBF file becomes an attribute in the XML file (property=value pairs). If the shape object is a poly-line (think city block), then xFrom, yFrom, xTo, yTo attributes are added to designate poly-line starting and ending points. For any other object type, I add longitude/latitude points ala Google KML files. The Shp2Xml utility will assume that all the shape file components are in the same folder and dump output to the console. So to generate XML file, run the following command from the command line:  

`c:\\>Shp2Xml SHP\_file\_name > xml\_file\_name`

## XML File Loading
In the download file, under SQL folder, there is a LoadTiger.sql file that contains all the code described throughout the rest of the article.
The loading portion is pretty simple:
```
DECLARE @hDoc int
DECLARE @xml xml
set @xml=(select convert(xml,BulkColumn, 2)
From openrowset(Bulk 'C:\temp\geotrans\edges.xml', single_blob) [rowsetresults])
exec sp_xml_preparedocument @hDoc OUTPUT, @xml
SELECT *
into geoStreet
FROM OPENXML(@hDoc, 'layer/shp', 1)
WITH (
	tlid		int '@TLID',
	prfx		varchar(2)   ,
	street		varchar(50)  '@FULLNAME',
	type		varchar(4)   ,
	LFROMADD	varchar(20) '@LFROMADD',
	LTOADD		varchar(20) '@LTOADD',
	RFROMADD	varchar(20) '@RFROMADD',
	RTOADD		varchar(20) '@RTOADD',
	fraddr		int  ,
	toaddr		int  ,
	zipl		varchar(5)   '@ZIPL',
	zipr		varchar(5)   '@ZIPR',
	frlon		decimal(9,5) '@xFrom',
	frlat		decimal(9,5) '@yFrom',
	tolon		decimal(9,5) '@xTo',
	tolat		decimal(9,5) '@yTo'
)
exec sp_xml_removedocument @hDoc
```

This segment loads c:\temp\geotrans\edges.xml (change as needed) into the geoStreet table. As you can see, I load only the following columns/attributes: FULLNAME, LFROMADD, LTOADD, RFROMADD, RTOADD, ZIPL, ZIPR, xFrom, yFrom, xTo, yTo.

The rest of the loading code is dedicated to the data clean up:
```
delete from geoStreet where street is null 
	or lfromadd is null or ltoadd is null
	or rfromadd is null or rtoadd is null
```

This segment removes non-street block elements from the data set - freeways, on/off ramps, rivers, ... Also as you can see, Tiger/Line data provides separate information for left/right side of the street. Sometimes the address numbers for left and right sides of the street are not the way I would like them - either non-numeric for one of the sides, or sometimes the addresses for the left side can be ascending, whereas for the right side they are descending - weird, hah! In order to make geo-coding process easier, I would like from and to addresses to be predictable ascending order. So the code below does clean this portion up:
```
update geoStreet set lFromAdd=rFromAdd where isnumeric(lFromAdd)=0
update geoStreet set rFromAdd=lFromAdd where isnumeric(rFromAdd)=0
update geoStreet set lToAdd=rToAdd where isnumeric(lToAdd)=0
update geoStreet set rToAdd=lToAdd where isnumeric(rToAdd)=0
update g set g.prfx=a.dir, g.type=a.tp, g.street=a.street
from geoStreet g cross apply fnParseAddr(g.street, 0) a

declare @b varchar(20), @tmpi int, @tmpn numeric(9,5), @tmpt numeric(9,5)
update geoStreet set 
	@b=LFROMADD, LFROMADD=LTOADD, LTOADD=@b
where   convert(int, LFROMADD)>convert(int, LTOADD)
	and convert(int, RFROMADD)<convert(int, RTOADD)
update geoStreet set 
	toaddr=(case when convert(int, RTOADD) > convert(int, LTOADD) _
	then RTOADD else LTOADD end),
	fraddr=(case when convert(int, RFROMADD) < convert(int, LFROMADD) _
	then RFROMADD else LFROMADD end)
where toaddr is null and fraddr is null
update geoStreet set 
	@tmpi=frAddr, frAddr=toAddr, toAddr=@tmpi,
	@tmpn=frlon, frlon=tolon, tolon=@tmpn,
	@tmpt=frlat, frlat=tolat, tolat=@tmpt
where frAddr > toAddr
```
The only remaining portion is dealing with the fact that the "All Lines" portion of the Tiger/Line data provides street name as one string. Instead of trying to join multiple files, I decided to hand-parse street name into the direction/name/type elements (see more about parsing later):
```
update g set g.prfx=a.dir, g.type=a.tp, g.street=a.street
from geoStreet g cross apply fnParseAddr(g.street, 0) a
```

## Address Parsing/Geo-coding
I found it overwhelming how many different formats of the addresses I had to process. Sometimes I would get everything parsed as a separate field - number, street apt, ... Sometimes I would get address line 1, city and zip. Sometimes it was address line 1 and address line 2. Also, sometimes I need geocoding performed in C# code where stored procedures are easy to execute, but sometimes I need it in SQL-Server script, where stored procedure means also a cursor with all the complexities of looping, checking error codes, ... So I decided to make it easy on myself: My geo-coding will be available as table-valued function, that would also perform address parsing and accept only one address string in the following format:

`StrNum StrDir StrName StrType # apt, City State Zip
Where:

StrNum is numeric
- StrDir - one of the N.S.E.W, North, South, East, West
- StrType - one of possible street types
- \# - separates possible apartment number
- , - first comma separates first address line from second address line
- Zip - 5 number optional zip code
- State - 2 character optional state
- City - everything else on the second address line
So the first portion of the fnParseAddr performs just that - chipping away string tokens one at a time trying to parse address:

Find the first comma to split address into lines 1 and 2:
```
set @i = charindex(',', @str)
if (@i > 0) 
	select  @city = replace(ltrim(substring(@str, @i+1, 999)), ',', ' '),
		@str = replace(rtrim(substring(@str, 1, @i-1)), ',', ' ')
```
Check if the first token is a number and load up street number if so:
```
set @i = charindex(' ', @str)
if (@i > 0 and isnumeric(substring(@str, 1, @i))=1) 
	select  @num = rtrim(substring(@str, 1, @i-1)), 
		@str = ltrim(substring(@str, @i+1, 999))
```
Check if the second token is street direction (North/East/West/South):
```
set @i = charindex(' ', @str)
if (@i > 0 and substring(@str, 1, @i-1) IN ('N','No','North','South','S','West','W','East','E'))
	select  @dir = rtrim(substring(@str, 1, 1)), 
		@str = ltrim(substring(@str, @i+1, 999)) 
```
And so on and so forth.

Once the address is parsed, we can try to figure out which city block it belongs to. Having all the city blocks loaded up in the database should make this job trivial - simple select where street name equals to what specified, number falls in the range. However street address is rarely correct. Most of the time, people don't know if it's a street or an avenue. North, south east and west street direction is rarely specified. Zip code is often wrong. So instead of simple match, we need to have a weights system - each match increases the chance of the correct address being found - if zip code matches add 3 to the score, if address is in the range add 2, if street type or direction matches - add 1. Use the best match record.

This translates to the following SQL code:
```
@wt = (case when @str=street then 5 else 0 end)
	+	(case when @zip IN (zipl, zipr) then 3 else 0 end)
	+ 	(case when @num between fraddr and toaddr then 2 else 0 end)
	+ 	(case when @dir=prfx then 1 else 0 end)
	+ 	(case when @tp=type then 1 else 0 end)
```
Now that the record that best matches our address is found, we need to find the actual latitude/longitude. To do that, we use interpolation: if city block contains addresses from 100 to 200, and we are looking for the house #125, it should be about a quarter from the start of the block:
```
select @ratio = 0.5
if @num between @fraddr and @toaddr or @num between @toaddr and @fraddr 
	select @ratio = 1.0 *(@num - @fraddr) / (@toaddr - @fraddr)
select 	@lat = (@ratio * (@tolat - @frlat) + @frlat) , 
	@lon = (@ratio * (@tolon - @frlon) + @frlon)
```

##Using the Code
Once you run LoadTiger.sql script, it will create a geoStreet table and fnParseAddr function. The table is used by the function to geo-code addresses. The function takes two parameters:
- Address - see previous section about accepted address formats
- ifGeocode - 0/1 flag to specify if only address parsing is needed or complete geo-coding needs to be performed

The function returns a table with just 1 row in it:

|  |  |  |
| --- | --- | --- |
| num	| varchar(20)	| street number| 
| dir	| varchar(1)	| street direction| 
| street	| varchar(100)	| street name| 
| tp	| varchar(20)	| street type| 
| apt	| varchar(20)	| apartment| 
| city	| varchar(100)	| city| 
| st	| varchar(2)	| state| 
| zip	| varchar(5)	| zip| 
| lat	| decimal(9,5)	| latitude| 
| lon	| decimal(9,5)	| longitude| 

To just parse address, use the following SQL-command:
```
select * from fnParseAddr('123 main st', 0)
```
To parse and geocode address, issue the following select statement:
```
select * from fnParseAddr('123 main st', 1)
```
To do batch geo-coding against some table in the database, issue the following command:
```
select tbl.stname, a.*
from SomeTable tbl 
	cross apply fnParseAddr(tbl.stname, 1) a
```
or, similarly to update information:
```
update tbl set tbl.lat=a.lat, tbl.lon=a.lon 
from SomeTable tbl 
	cross apply fnParseAddr(tbl.stname, 1) a
where a.lat != 0 
```
