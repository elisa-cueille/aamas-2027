/**
* Name: faileddestination
* Based on the internal empty template. 
* Tags: 
*/


model failed_destination

species failed_destination {
    int person_id;
    int trip_number;
    point failed_point;     
    point origin_point;      
    
    aspect base {
        draw circle(10#m) at: origin_point color: #orange border: #darkorange;
        
        draw circle(10#m) at: failed_point color: #red border: #darkred;
        
        draw line([origin_point, failed_point]) color: #red width: 5 end_arrow:500#m;
        
    }
}