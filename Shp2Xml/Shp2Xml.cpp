// Shp2Xml.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"
#include <math.h>
void chkCond(int cond, char *msg) {
	if (cond)
		return;
	fprintf(stderr, msg);
	exit(-1);
}
char *chkXml(char *buf) {
	for (char *s = buf; *s; s++)
		if (*s == '&') *s = '/';
		else if (*s == '"') *s = '\'';
		else if (*s == 'í') *s = 'i';
		else if (*s == 'ó') * s = 'o';
		else if (*s > 127) *s = '~';
	return buf;
}

static const double AngRad = 0.01745329252;		//number of radians in a degree
static const double Pi2 = 3.141592653582 / 2;
static const double Pi4 = Pi2 / 2;	
static const double A = 6378137;	//major radius of ellipsoid, map units
static const double E = 0.0818879;	//eccentricity of ellipsoid
//NAD27
//Const A As Integer = 6378206               'major radius of ellipsoid, map units
//Const E As Double = 0.0822719             'eccentricity of ellipsoid
struct Conversion {
	double X0 ;		//PARAMETER["False_Easting",6561666.666666666],
	double Y0 ;		//PARAMETER["False_Northing",1640416.666666667],
    double M0 ;		//PARAMETER["Central_Meridian",-118.0],
    double P1 ;		//PARAMETER["Standard_Parallel_1",34.03333333333333],
    double P2 ;		//PARAMETER["Standard_Parallel_2",35.46666666666667],
	double P0 ;		//PARAMETER["Latitude_Of_Origin",33.5],
	double K  ;		//UNIT["Foot_US",0.3048006096012192]

	double F, n, rho0;

	Conversion() {
		X0 = Y0 = M0 = P0 = P1 = P2 = 0;
		F = n = rho0 = 0;
		K = 1;
	}
	void Load(char *file) {
		char *wp = strrchr(file, '.'), *vp, *ep;
		strcpy(wp, ".prj");	
		FILE *fp = fopen(file, "r");
		if (fp == NULL)
			return;
		char buf[1024];
		int len = fread(buf, 1, sizeof(buf), fp);
		fclose(fp);
		if (len == 0)
			return;
		buf[len] = 0;
		if (!_stricmp(buf, "PROJECTION"))
			return;
		chkCond(_stricmp(buf, "Lambert_Conformal_Conic"), "Only Lambert_Conformal_Conic projection is supported");
		for (wp = buf; wp < buf + len; wp = ep + 1) {
			if (NULL == (wp = strstr(wp, "[\""))
			||  NULL == (ep = strstr(wp, "]")))
				break;
			if (NULL == (vp = strstr(wp += 2, "\",")) || vp > ep)
				continue;
			*ep = *vp = 0; vp += 2;
			if (_stricmp(wp, "False_Easting") == 0)				X0 = atof(vp);
			else if (_stricmp(wp, "False_Northing") == 0)		Y0 = atof(vp);
			else if (_stricmp(wp, "Central_Meridian") == 0)		M0 = atof(vp) * AngRad;
			else if (_stricmp(wp, "Standard_Parallel_1") == 0)	P1 = atof(vp) * AngRad;
			else if (_stricmp(wp, "Standard_Parallel_2") == 0)	P2 = atof(vp) * AngRad;
			else if (_stricmp(wp, "Latitude_Of_Origin") == 0)	P0 = atof(vp) * AngRad;
			else if (_stricmp(wp, "Foot_US") == 0)				K = atof(vp);
		}
		double m1 = cos(P1) / sqrt(1 - E*E * sin(P1)*sin(P1));
		double m2 = cos(P2) / sqrt(1 - E*E * sin(P2)*sin(P2));
		
		double t0 = tan(Pi4 - P0/2) / pow((1 - E * sin(P0)) / (1 + E * sin(P0)), E/2);
		double t1 = tan(Pi4 - P1/2) / pow((1 - E * sin(P1)) / (1 + E * sin(P1)), E/2);
		double t2 = tan(Pi4 - P2/2) / pow((1 - E * sin(P2)) / (1 + E * sin(P2)), E/2);
		
		n = log(m1 / m2) / log(t1 / t2);
		F = m1 / (n * pow(t1 , n));
		rho0 = A * F * pow(t0 , n);
	}
	void Convert(double &x, double &y) {
		if (P0 == 0 && P1 == 0 && P2 == 0)
			return;
        x = (x - X0) * K;
        y = (y - Y0) * K;
		double rho = sqrt(x * x + (rho0 - y) * (rho0 - y));
		double theta = atan(x / (rho0 - y));
		double t = pow((rho / (A * F)) , (1 / n));
		y = Pi2 - (2 * atan(t));
		for (double Lat0 = y + 1; fabs(y - Lat0) > 0.0000002; ) {
			Lat0 = y;
			y = Pi2 - 2 * atan(t * pow((1 - E * sin(Lat0)) / (1 + E * sin(Lat0)), E/2));
		}
		x = ((theta / n) + M0) / AngRad;
		y /= AngRad;
	}
};

int main(int argc, char* argv[]) {
	char	col[12], buf[256];
	int		j, nDecimals, shpRecs;
	double 	adfMinBound[4], adfMaxBound[4];
	Conversion conv;

	chkCond(argc > 1, "shp2xml xbase_file\n" );

	strcpy(buf, argv[1]);
	char *ext = strrchr(buf, '.');
	chkCond(ext != NULL, "File name doesnt have an extention");
	strcpy(ext, ".dbf");	

	DBFHandle	hDBF = DBFOpen(buf, "rb" );
	chkCond(hDBF != NULL, "Failed to open DBF file");
	chkCond( DBFGetFieldCount(hDBF) != 0, "There are no fields in this table!\n" );

	strcpy(ext, ".shp");
	SHPHandle	hSHP = SHPOpen(buf, "rb" );
	chkCond(hSHP != NULL, "Failed to open SHP file");

	conv.Load(buf);
	int dbfRecs = DBFGetRecordCount(hDBF);
    SHPGetInfo( hSHP, &shpRecs, &j, adfMinBound, adfMaxBound );
	chkCond(dbfRecs = shpRecs, "Number of DBF records doesn't match number of SHP records");

	printf("<layer>\n");
	for (int rec = 0; rec < dbfRecs; rec++ ) {
		printf("<shp\n");
		for (int i = 0; i < DBFGetFieldCount(hDBF); i++) {
			DBFFieldType eType = DBFGetFieldInfo( hDBF, i, col, &j, &nDecimals );
			if (DBFIsAttributeNULL( hDBF, rec, i )) 
				continue;
			switch( eType ) {
			  case FTString:
				  printf("\t%s=\"%s\"\n", col, chkXml((char *)DBFReadStringAttribute(hDBF, rec, i)), col );
				  break;

			  case FTInteger:
				  printf("\t%s='%d'\n", col, DBFReadIntegerAttribute( hDBF, rec, i ), col ); 
				  break;

			  case FTDouble:
				  printf("\t%s='%f'\n", col, DBFReadDoubleAttribute( hDBF, rec, i ), col );
				  break;
			}
		}
		SHPObject *shp = SHPReadObject( hSHP, rec );
		int cnt = shp->nVertices;
		if (shp->nParts > 1)
			cnt = shp->panPartStart[1];
		if (shp->nSHPType == SHPT_POLYGON) {
			printf(">\n\t<poly>\n");
			for (int i = 0; i < cnt; ) {
				conv.Convert(shp->padfX[i], shp->padfY[i]);
				printf(" %.5f %.5f", shp->padfX[i], shp->padfY[i]);
				if ((++i % 5) == 0)
					printf("\n");
			}
			printf("\n\t</poly>\n");
			printf("</shp>\n");
		}
		else {
			if (cnt >= 2) {
				conv.Convert(shp->padfX[0], shp->padfY[0]);
				conv.Convert(shp->padfX[-1], shp->padfY[-1]);
				printf("\txFrom='%.5f' yFrom='%.5f' xTo='%.5f' yTo='%.5f'\n",
					shp->padfX[0], shp->padfY[0], shp->padfX[cnt-1], shp->padfY[cnt-1]);
			}
			printf("/>\n");
		}
	}
	printf("</layer>\n");
	DBFClose(hDBF);
	SHPClose(hSHP);
	return( 0 );
}

