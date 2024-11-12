if exists (select * from dbo.sysobjects where id = object_id(N'dbo.fnParseAddr') and xtype in (N'FN', N'IF', N'TF'))
	drop function dbo.fnParseAddr
GO
CREATE FUNCTION dbo.fnParseAddr(@addr varchar(256), @lookup int)
	RETURNS @ret TABLE (
		num		varchar(20),	dir	varchar(1),
		street	varchar(100),	tp	varchar(20), apt varchar(20),
		city	varchar(100),	st	varchar(2),  zip varchar(5),
		lat		decimal(9,5),	lon	decimal(9,5)
	) AS BEGIN
	declare @str varchar(100), @city varchar(100), @num varchar(20), 
		@apt varchar(20), @dir varchar(20), @tp varchar(20), @state varchar(2), 
		@zip varchar(5), @lat decimal(9,5), @lon decimal(9,5), 
		@wt int, @i int,
		@fraddr int, @frlon decimal(9,5), @frlat decimal(9,5), 
		@toaddr int, @tolon decimal(9,5), @tolat decimal(9,5), 
		@ratio decimal(9,5), @str1 varchar(128), @str2 varchar(128)

	select @str = replace(replace(@addr, '.', ' '), '&', '/'),
		@city='', @num='', @apt='', @dir='', @tp='', @state='', @zip='',
		@lat=0, @lon=0, @wt = -1
	set @str = replace(replace(replace(@str, '1/2', ' '), '1/4', ' '), '3/4', ' ')
	set @str = Replace(replace(replace(@str, ' Apt ', ' # '), ' Unit ', ' # '), ' No ', ' # ')
	set @str = Replace(Replace(replace(@str, ' Appartment ', ' '), ' Suite ', ' # '), ' ste ', ' # ')
	set @str = ltrim(rtrim(replace(@str, '  ', ' ')))
	set @str = replace(@str, ', #', ' #')

	set @i = charindex(',', @str)
	if (@i > 0) 
		select  @city = replace(ltrim(substring(@str, @i+1, 999)), ',', ' '),
				@str = replace(rtrim(substring(@str, 1, @i-1)), ',', ' ')

	set @i = charindex(' ', @str)
	if (@i > 0 and isnumeric(substring(@str, 1, @i))=1) 
		select  @num = rtrim(substring(@str, 1, @i-1)), 
				@str = ltrim(substring(@str, @i+1, 999))

	set @i = charindex(' ', @str)
	if (@i > 0 and substring(@str, 1, @i-1) IN ('N','No','North','South','S','West','W','East','E'))
		select  @dir = rtrim(substring(@str, 1, 1)), 
				@str = ltrim(substring(@str, @i+1, 999))

	set @i = charindex('#', @str)
	if (@i > 0) 
		select  @apt = ltrim(substring(@str, @i+1, 999)),
				@str = rtrim(substring(@str, 1, @i-1))

	set @i = len(@str) - charindex(' ', reverse(@str))
	if (@i > 0 and @i < len(@str)
	and substring(@str, @i+2, 999) IN ('N','No','North','South','S','West','W','East','E')) 
		select  @dir = substring(@str, @i+2, 1),
				@str = rtrim(substring(@str, 1, @i))

	set @i = len(@str) - charindex(' ', reverse(@str))
	if (@i > 0 and @i < len(@str)) begin
		set @str1 = ltrim(substring(@str, @i+1, 999))
		set @str1 = case @str1
				when 'Plaza'	then 'Plz'
				when 'Center'	then 'Ctr'
				when 'Circle'	then 'Cir'
				when 'Terrace'	then 'Ter' when 'Terr'	then 'Ter'
				when 'Avenue'	then 'Ave' when 'Av'	then 'Ave'
				when 'Pkwy'		then 'Pky'
				when 'Bl'		then 'Blvd' when 'Boulevard' then 'Blvd'
				when 'Street'	then 'St'
				when 'Wy'		then 'Way'
				when 'Drive'	then 'Dr'
				when 'Place'	then 'Pl'
				when 'Lane'		then 'Ln'
				when 'Road'		then 'Rd'
				when 'Court'	then 'Ct'
			else @str1 end
		if (charindex(';'+@str1+';', ';blvd;ave;pl;dr;st;ctr;ct;pky;row;hwy;way;rd;cir;plz;ter;walk;ln;aly;') > 0)
		select  @tp = @str1,
				@str = rtrim(substring(@str, 1, @i))
	end
	
	set @str1 = right(@city, 5)
	if (len(@city) >= 5 and isnumeric(@str1)=1 and @str > '00000')
		select @zip = @str1,
				@city = rtrim(substring(@city, 1, len(@city)-5))

	set @i = len(@city) - charindex(' ', reverse(@city))
	if (@i > 0 and @i < len(@city) and len(ltrim(substring(@city, @i+1, 999)))=2)
		select  @state= ltrim(substring(@city, @i+1, 9999)),
				@city = rtrim(substring(@city, 1, @i))

	if (@lookup=1) begin
		set @i = charindex('/', @str)
		if @i > 0 begin
			select @str1 = ltrim(rtrim(left(@str, @i-1))),
				   @str2 = ltrim(rtrim(substring(@str, @i+1, len(@str))))
			set @i = charindex(' ', @str1)
			if (@i > 0) set @str1 = rtrim(left(@str1, @i))
			set @i = charindex(' ', @str2)
			if (@i > 0) set @str2 = rtrim(left(@str2, @i))
			select top 1 
				@lat = (case when g1.frlat=g2.frlat then g1.frlat else g1.tolat end),
				@lon = (case when g1.frlon=g2.frlon then g1.frlon else g1.tolon end),
				@zip=g1.zipr
				--, @state=g1.state
			from geoStreet g1 (nolock) join geoStreet g2 (nolock)
				 on (g1.frlon=g2.frlon or g1.tolon=g2.frlon or g1.frlon=g2.tolon or g1.tolon=g2.tolon)
				and (g1.frlat=g2.frlat or g1.tolat=g2.frlat or g1.frlat=g2.tolat or g1.tolat=g2.tolat)
			and g1.street like @str1+'%' and g2.street like @str2+'%' 
		end else begin
			select top 1 @wt = (
					(case when @str=street then 5 else 0 end)
				+	(case when @zip IN (zipl, zipr) then 3 else 0 end)
				+ 	(case when @num between fraddr and toaddr then 2 else 0 end)
				+ 	(case when @dir=prfx then 1 else 0 end)
				+ 	(case when @tp=type then 1 else 0 end)
				), @dir=right(prfx,1), @tp=type, @zip=zipr, -- @state=state, 
					@fraddr=fraddr, @frlon=frlon, @frlat=frlat, 
					@toaddr=toaddr, @tolon=tolon, @tolat=tolat
			from geoStreet (nolock)
			where @str = street
			order by 1 desc, abs((fraddr+toaddr) / 2 - @num)
			if (@wt != -1) begin
				select @ratio = 0.5
				if @fraddr != @toaddr and @num between @fraddr and @toaddr 
					select @ratio = 1.0 *(@num - @fraddr) / (@toaddr - @fraddr)
				select @lat = (@ratio * (@tolat - @frlat) + @frlat) , 
					   @lon = (@ratio * (@tolon - @frlon) + @frlon) 
			end
		end
	end
	insert into @ret (num, dir, street, tp, apt, city, st, zip, lat, lon)
	values (@num, @dir, @str, @tp, @apt, @city, @state, @zip, @lat, @lon)
	return
END
GO

if exists (select * from dbo.sysobjects where id = object_id(N'geoStreet') and OBJECTPROPERTY(id, N'IsUserTable') = 1)
	drop table geoStreet
go

DECLARE @hDoc int
DECLARE @xml xml
set @xml=(select convert(xml,BulkColumn, 2)
From openrowset(Bulk 'C:\temp\Shp2Xml\Debug\y.xml', single_blob) [rowsetresults])
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

go
delete from geoStreet where street is null 

ChkNumAddr:
	update geoStreet set LTOADD=left(LTOADD,len(LTOADD)-1)
	where isNull(LTOADD,'')!='' AND isNumeric(LTOADD)=0
if @@rowcount>0 goto ChkNumAddr
	update geoStreet set RTOADD=left(RTOADD,len(RTOADD)-1)
	where isNull(RTOADD,'')!='' AND isNumeric(RTOADD)=0
if @@rowcount>0 goto ChkNumAddr
	update geoStreet set LFROMADD=left(LFROMADD,len(LFROMADD)-1)
	where isNull(LFROMADD,'')!='' AND isNumeric(LFROMADD)=0
if @@rowcount>0 goto ChkNumAddr
	update geoStreet set RFROMADD=left(RFROMADD,len(RFROMADD)-1)
	where isNull(RFROMADD,'')!='' AND isNumeric(RFROMADD)=0
if @@rowcount>0 goto ChkNumAddr

update geoStreet set 
	LFROMADD=isnull(NullIf(LFROMADD,''), RFROMADD), RFROMADD=isnull(NullIf(RFROMADD,''), LFROMADD),
	LTOADD  =isnull(NullIf(LTOADD,''),   RTOADD),   RTOADD  =isnull(NullIf(RTOADD,''), LTOADD)
where IsNull(LFROMADD,'')='' or IsNull(LTOADD,'')='' or IsNull(RFROMADD,'')='' or IsNull(RTOADD,'')='' 

delete from geoStreet 
where  IsNull(lfromadd,'')='' or IsNull(ltoadd,'')='' 
	or IsNull(rfromadd,'')='' or IsNull(rtoadd,'')='' 
update g set g.prfx=a.dir, g.type=a.tp, g.street=a.street
from geoStreet g cross apply fnParseAddr(g.street, 0) a

declare @b varchar(20), @tmpi int, @tmpn numeric(9,5), @tmpt numeric(9,5)
update geoStreet set 
	@b=LFROMADD, LFROMADD=LTOADD, LTOADD=@b
where   convert(int, LFROMADD)>convert(int, LTOADD)
	and convert(int, RFROMADD)<convert(int, RTOADD)
update geoStreet set 
	toaddr=(case when convert(int, RTOADD) > convert(int, LTOADD) then RTOADD else LTOADD end),
	fraddr=(case when convert(int, RFROMADD) < convert(int, LFROMADD) then RFROMADD else LFROMADD end)
where toaddr is null and fraddr is null
update geoStreet set 
	@tmpi=frAddr, frAddr=toAddr, toAddr=@tmpi,
	@tmpn=frlon, frlon=tolon, tolon=@tmpn,
	@tmpt=frlat, frlat=tolat, tolat=@tmpt
where frAddr > toAddr
go

alter table geoStreet drop column lfromadd
alter table geoStreet drop column ltoadd
alter table geoStreet drop column rfromadd
alter table geoStreet drop column rtoadd
if not exists (select * from dbo.sysindexes where name = 'IX_geoStreet_str' and id = object_id(N'dbo.geoStreet'))
	CREATE CLUSTERED INDEX IX_geoStreet_str ON dbo.geoStreet (street)
GO
