/**
* Name: metro
* Based on the internal empty template. 
* Tags: 
*/


model province
import "../Parameters.gaml"

species province{
	rgb color<-natural_color["boundary_province"];
	bool wireframe <- true;
	int width <- 2;
	aspect base{
		draw shape color:color wireframe:wireframe width:width;
	}
}

