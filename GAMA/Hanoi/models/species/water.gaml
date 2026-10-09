/**
* Name: road
* Based on the internal empty template. 
* Tags: 
*/


model water

import "../Parameters.gaml"


species water{
	string type;
	rgb color <- natural_color[type];
	aspect base{
		draw shape color: color;
	}
}

