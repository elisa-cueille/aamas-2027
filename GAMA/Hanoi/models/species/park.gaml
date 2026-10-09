/**
* Name: road
* Based on the internal empty template. 
* Tags: 
*/


model park

import "../Parameters.gaml"


species park{
	string type;
	rgb color <- natural_color[type];
	aspect base{
		draw shape color: color;
	}
}

