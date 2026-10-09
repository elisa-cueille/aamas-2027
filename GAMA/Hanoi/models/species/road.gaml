/**
* Name: road
* Based on the internal empty template. 
* Tags: 
*/


model road
import "../Parameters.gaml"

species road{
	string highway;
	int maxspeed;
	int lanes;
	string oneway;
	rgb color<-mobility_color["road"];
	aspect base{
		draw shape color:color width:2;
	}
}

