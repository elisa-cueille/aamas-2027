/**
* Name: road
* Based on the internal empty template. 
* Tags: 
*/


model mobility_survey
import "../Parameters.gaml"

species mobility_survey{
	rgb color<-natural_color["boundary"];
	bool wireframe <- true;
	int width <- 2;
	aspect base{
		draw shape color:color wireframe:wireframe width:width;
	}
}

