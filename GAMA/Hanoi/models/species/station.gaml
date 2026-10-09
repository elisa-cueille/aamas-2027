/**
* Name: station
* Based on the internal empty template. 
* Tags: 
*/


model station
import "../Parameters.gaml"

species station{
	
	string line_id;
	int stop_id;
	int stop_seque;
	string mode;
	float avg_wait;
	bool created;
	
	rgb color;

	aspect base{
		draw circle(100) color:color;
	}
	
	aspect schematic{
		draw circle(50) color: rgb(52, 152, 219) at: location+{0,0,0.5};
	}
}

 