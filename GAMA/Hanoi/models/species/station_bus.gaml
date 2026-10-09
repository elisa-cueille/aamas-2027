/**
* Name: stationbus
* Based on the internal empty template. 
* Tags: 
*/


model stationbus
import "station.gaml"

species station_bus parent: station{
	init { mode <- "BUS";
		color<-mobility_color["BUS"];
	}
}
 