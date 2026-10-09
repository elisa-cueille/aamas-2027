/**
* Name: road
* Based on the internal empty template. 
* Tags: 
*/


model counting_point

species counting_point{
	string name;
	int capacity <-250;
	geometry shape <-square(capacity);
	rgb color<-#blue;
	aspect base{
		draw shape color:color;
	}
}

