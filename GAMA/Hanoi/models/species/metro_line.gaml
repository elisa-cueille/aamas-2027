/**
* Name: metro
* Based on the internal empty template. 
* Tags: 
*/


model metro_line
import "../Parameters.gaml"
import "station_metro.gaml"

species metro_line{
	string line;
	int year; 
	string line_color;
	list<station_metro> stations;

	aspect default{
		draw shape color:mobility_color["MTR"] width:(year <= simulation_year ? 10 : 2);
	}
}

