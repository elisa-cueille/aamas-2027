/**
* Name: trip
* Based on the internal empty template. 
* Tags: 
*/


model trip

/* Insert your model definition here */
import "../Parameters.gaml"
species trip {
	//csv
	int trip_number;
	int person_id;
	date day;
	int dep_id; //['1', '2', '3', '4', '5', '6', '7', '8', '9']
	string origin_purpose; // ['Home', 'Work', 'Education', 'Shop', 'Others']
	string destination_purpose; // ['Home', 'Work', 'Education', 'Shop', 'Others']
	string main_mode; // ['Bus', 'Marche seule', 'Moto-taxi', 'Métro', 'Scooter - conducteur', 'Scooter - passager', 'Taxi', 'Voiture - conducteur', 'Voiture - passager', 'Vélo']
	string mode_1; //['Bus', 'Marche seule', 'Moto-taxi', 'Métro', 'Scooter - conducteur', 'Scooter - passager', 'Taxi', 'Voiture - conducteur', 'Voiture - passager', 'Vélo', 'marcher seule']
	string mode_2; //['Bus', 'Moto-taxi', 'Métro', 'Scooter - conducteur', 'Scooter - passager', 'Train', 'Voiture - passager']
	string mode_3; //[]
	//only 5 cases where main mode is different from mode 1,2 or 3 (over 6867 trips)
	date departure_time;
	date arrival_time; // null
	float duration_minutes;
	point origin_point;
    point destination_point;
    bool showInClient <- false;
    bool display_trip <- false;
    point real_start;
    point real_end;
    
    reflex when: (departure_time + 1000#s) < current_date {
    	display_trip <- false;
    }
    	aspect trips_metro_too_far {
		//if((int(self) = cycle)){
		if(display_trip){
	  		path the_path;

	  		draw circle(20) color:mode_color[main_mode];
//			draw "trip n°: " + trip_number  at:origin_point color:mode_color[main_mode] font:simulationFont;  

			//draw "trip " + i at:line(t.origin_point, t.destination_point).location color:mode_color[t.main_mode] size:1;
		    the_path <- metro_graph_weighted path_between (real_start, real_end);
		    //draw "path " + i at:the_path.shape.location + {i,0}color:mode_color[t.main_mode] size:1;
		    draw line(the_path.shape.points) color: mode_color[main_mode] width: 4 end_arrow: 10;	
		}	
	}
	
}