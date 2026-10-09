/**
* Name: stationmetro
* Based on the internal empty template. 
* Tags: 
*/


model stationmetro
import "station.gaml"


species station_metro parent: station{
	init { mode <- "metro";
		color<-metro_color[line_id];
	}
}

