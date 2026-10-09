/**
* Name: metro
* Based on the internal empty template. 
* Tags: 
*/


model bus_lines
import "../Parameters.gaml"

species bus_lines{

	string line_id;
	rgb color<-mobility_color["BUS"];

	aspect default{
		draw shape color:color width:2;
	}
}

