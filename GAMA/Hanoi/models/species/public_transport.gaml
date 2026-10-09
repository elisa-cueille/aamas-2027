/**
* Name: publictransport
* Based on the internal empty template. 
* Tags: 
*/


model publictransport


import "../Parameters.gaml"

species public_transport {

    // ── Commun ────────────────────────────────────────────────────────────
    string edge_type;       // "road" | "bus" | "metro " | "connector"
    float  weight;          // metres for road/bus/metro, 0 or 5 (min) for connectors

    // ── Attributs road ────────────────────────────────────────────────────
    string highway;
    int    maxspeed;
    int    lanes;
    string   oneway;

    // ── Attributs bus ─────────────────────────────────────────────────────
    string line_id;         // ex. "06A", "E11", "BRT01"
    int sequence;
    int stop_start;
    int stop_end;

    // ── Attributs connector ───────────────────────────────────────────────
    string station_id;      // stop_id de la station reliée
    string connector_dir;   // "alighting" (bus->road, poids 0) | "boarding" (road->bus, poids 5)
	
	float connector_speed;
	
	float connected_distance;
	
	rgb color<-mobility_color["PT"];
	
    aspect multimode {
        if(edge_type = "metro" and display_metro){
    		draw shape color:metro_color[line_id] width:3 end_arrow:3;
    	} else if (edge_type = "bus" and display_bus){
    		draw shape color:mobility_color["BUS"] width:2 end_arrow:2;
    	}
    	}
    
    
    aspect public {
    	if(edge_type = "metro"){
    		draw shape color:metro_color[line_id] width:3 end_arrow:3;
    	} else if (edge_type = "bus"){
    		draw shape color:mobility_color["BUS"] width:2 end_arrow:2;
    	}
    }
    
    aspect schematic {
    	    if (edge_type = "road"){
    	      draw shape color:mobility_color[edge_type] width:2;
    	    }
	    	if (edge_type = "connector"){
	     	  draw shape color: #red width:1;
	    	}
	    	if (edge_type = "bus" or edge_type = "metro" ){
	     	  draw shape color: (edge_type = "bus" ? mobility_color["BUS"] : mobility_color["MTR"]) width: 3 at: location + {0,0,0.5};
	    	}
    }

}

