/**
* Name: person
* Based on the internal empty template. 
* Tags: 
*/
model person

import "trip.gaml"
import "failed_destination.gaml"
import "affordance_cell.gaml"
import "../Parameters.gaml"
import "../Model.gaml"

species person skills: [moving] {
	// from csv
	int person_id;
	string sex;//['Femme', 'Homme']
	int age;
	string current_status;//['Actif', 'Personne au foyer', 'Retraité', 'Sans emploi', 'Étudiant ou élève']
	string education_level; //['Baccalauréat', 'Enseignement supérieur', 'Niveau secondaire']
	string home_address;
	string school_work_address;
	int gas_car;
	int electric_car;
	int gas_scooter;
	int electric_scooter;
	int manual_bike;
	int electric_bike;
	string driving_license; //['Aucun', 'Scooter', 'Voiture']
	string bus_subscription; // Oui Non
	int weight_survey;
	rgb color;
	// other attributes
	list<trip> trips <- [];
	trip current_trip;
	string trip_structure;
	date time_departure_current_trip;
	int num_trip <- 0;
	point target;
	float speed_m_s <- 11.1;
	string current_activity <- "Home";
	unknown allowed_graph <- road_graph;

	// trip_steps : chaque element est une map avec "target", "mode", "speed"
	list<map<string, unknown>> trip_steps <- [];
	string current_mode;
	string mode_survey;
	string mode_utility;
	
	float real_distance_m <- 0.0;
	float real_trip_duration_min <- 0.0;

	float walk_duration_min    <- 0.0;
	float walk_distance_m      <- 0.0;
	
	float transit_duration_min <- 0.0;
	float transit_distance_m   <- 0.0;
	
	float waiting_duration_min <- 0.0;
	
	date time_current_mode_start;
	point previous_target;

	path full_path;
	
	// for build_transit_steps function
	string last_transit_mode  <- "";
	float  last_transit_speed <- 0.0;
	
	point current_start_point;
	point current_end_point;

	
	bool drawAllTrips<-false;
	
	bool moveInClient <- true;

	// Utility error terms
	map<string, float> eps_terms <- [];

	map<string, float> internal_needs <- ["hunger"::0.0, "shop"::0.0, "leisure"::0.0];
	string active_satisfied_need <- "";
	affordance_cell current_affordance_cell <- nil;
	date activity_end_time <- nil;
	point home_location <- nil;
	point work_location <- nil;
	point education_location <- nil;
	point affordance_origin_location <- nil;
	string affordance_origin_activity <- "Home";

	string agenda_state <- "At_Home"; // "At_Home", "Commuting", "At_Mandatory", "At_Midday_Break", "At_Discretionary"
	bool schedule_initialized <- false;
	
	// Morning mandatory anchor schedule
	date morning_dep_time <- nil;
	float mandatory_duration_min <- 0.0;
	float remaining_mandatory_min <- 0.0;
	bool morning_commute_done <- false;
	
	// Emergent break attributes (triggered by internal needs vs affordances)
	bool is_on_break <- false;
	bool break_taken_today <- false;
	bool morning_errand_eval_done <- false;
	bool is_business_errand <- false;
	bool has_morning_student_job <- false;
	bool has_afternoon_student_job <- false;
	bool has_evening_student_job <- false;
	date next_affordance_eval_time <- nil;
	
	// Evening shift release
	bool evening_return_done <- false;
	bool evening_outing_done <- false;
	
	// School escort attributes
	bool is_school_escort <- false;
	int escort_stage <- 0; // 0: before drop-off, 1: drop-off done, 2: pick-up done
	date escort_dropoff_time <- nil;
	date escort_pickup_time <- nil;

	init {
		list<string> all_modes <- ["SD", "CD", "PT", "W", "B", "MTR", "BUS"];
		loop m over: all_modes {
			// generate a number between 0 and 1
			float u <- rnd(0.00001, 0.99999); 
			//  transform to have a Gumbel distribution
			eps_terms[m] <- -ln(-ln(u));
		}
		
		// Initialize individual need levels (hunger, shop, leisure) with variation to reproduce morning (06:30-09:00) vs afternoon/evening peaks
		if (generate_activities) {
			internal_needs["hunger"] <- rnd(0.0, 0.14);
			// Continuous stock state across replenishment cycle [0, tau_shop] (daily shop rate = (16 * lambda) / tau)
			if (current_status = "Retraité") {
				// Empirical replenishment cycle: 33.5% shop on a given day (every 3 days); 66.5% pantry stocked
				// Morning market shoppers start on [0.408, 0.442] so accumulation (0.0093/h) hits survey peaks: 6h (~13), 7h (~21), 8h (~7)
				bool shops_today <- flip(0.335);
				internal_needs["shop"] <- shops_today ? rnd(0.408, 0.442) : rnd(0.02, 0.22);
				internal_needs["leisure"] <- shops_today ? rnd(0.06, 0.22) : rnd(0.52, 0.68);
			} else if (current_status = "Personne au foyer") {
				// Empirical replenishment cycle: 51.0% shop on a given day (every 2 days); 49.0% pantry stocked
				bool shops_today <- flip(0.51);
				internal_needs["shop"] <- shops_today ? rnd(0.408, 0.442) : rnd(0.05, 0.25);
				internal_needs["leisure"] <- shops_today ? rnd(0.06, 0.22) : rnd(0.38, 0.54);
			} else if (current_status = "Sans emploi") {
				internal_needs["shop"] <- rnd(0.05, 0.35);
				internal_needs["leisure"] <- rnd(0.48, 0.58);
			} else if (current_status = "Actif" and work_location = nil) {
				// Home-based / informal workers participate in morning wet market shopping -> reproduces H-S-H
				internal_needs["shop"] <- rnd(0.36, 0.48);
				internal_needs["leisure"] <- rnd(0.20, 0.45);
			} else {
				// Commuting Workers and Students: shop need begins in mid-cycle [0.08, 0.38]
				internal_needs["shop"] <- (current_status = "Étudiant ou élève") ? rnd(0.08, 0.38) : rnd(0.08, 0.40);
				internal_needs["leisure"] <- rnd(0.10, 0.30);
			}
		}
	}
	// ── Helpers ─────────────────────────────────────────────────────────────

	/**
	 * add a step to trip_steps.
	 * topology_graph = true  → agent moves on topology(world)
	 * topology_graph = false → agent moves on the mode graph 
	 */
	action build_step(point pt, string mode, float spd, bool topology_graph) {
		map<string, unknown> one_step;
		one_step["target"] <- pt;
		one_step["mode"]   <- mode;
		one_step["speed"]  <- spd;
		one_step["graph"] <- topology_graph;
		trip_steps << one_step;
	}

	/**
	 * apply the next step and update current_mode, speed_m_s,
	 * target et allowed_graph
	 */
	action apply_next_step() {
		time_current_mode_start <- current_date;
		map<string, unknown> next <- first(trip_steps);
		current_mode <- string(next["mode"]);
		speed_m_s    <- float(next["speed"]);
		target       <- point(next["target"]);
		
		
		if bool(next["graph"]) {
			allowed_graph <- world_topology_graph;
		} else if current_trip.main_mode = "PT" {
			allowed_graph <- multimodal_graph;
		} else if current_trip.main_mode = "MTR" {
			allowed_graph <- metro_graph;
		} else if current_trip.main_mode = "BUS" {
			allowed_graph <- bus_graph;
		} else {
			allowed_graph <- road_graph;
		}
		
		remove next from: trip_steps;
		
	}


	/**
	 * accumulate the duration depending on the mode in time_current_mode_start 
	 * called at the end of each step
	 */
	action accumulate_mode_duration(float duration_min) {
		if current_mode in walk_modes {
			walk_duration_min <- walk_duration_min + duration_min;
		} else if current_mode in transit_modes {
			transit_duration_min <- transit_duration_min + duration_min;
		} else if current_mode in wait_modes {
			waiting_duration_min <- waiting_duration_min + duration_min;
		}
	}

	/**
	 * put the agent directly at the destination point, save the fail
	 * when no path is found
	 */
	action abort_trip(string trip_mode, path p_null) {
		if (debug) {
			write "⚠️ Aborted " + trip_mode + " — trip " + current_trip.trip_number + ", person " + person_id + " path "+p_null;
		}
		create failed_destination {
			person_id    <- myself.person_id;
			trip_number  <- myself.current_trip.trip_number;
			failed_point <- myself.target;
			origin_point <- myself.location;
		}
		if (generate_activities and current_affordance_cell != nil) {
			current_affordance_cell.release_slot(current_trip.destination_purpose);
			current_affordance_cell <- nil;
		}
		location         <- current_trip.destination_point;
		current_activity <- current_trip.destination_purpose;
		target           <- nil;
		current_trip     <- nil;
		walk_duration_min    <- 0.0;
		transit_duration_min <- 0.0;
		waiting_duration_min <- 0.0;
		trip_steps <- [];
	}

	/**
	 * build intermediate steps
	 * 
	 * - network_type : "metro" ou "bus"  (rb.edge_type)
	 * - transit_mode : "Métro" ou "Bus"
	 * - walk_mode    : "Marche with Metro" ou "Marche with Bus"
	 * - waiting_mode : "Waiting Metro"    ou "Waiting Bus"
	 */
	action build_transit_steps(list edges, string transit_mode, string walk_mode, string waiting_mode, point end_point) {
		string prev_mode <- "";
		float  prev_speed <- 0.0;

		loop edge over: edges {
			
			public_transport rb <- public_transport(edge);
			string rb_edge_type     <- string(rb get "edge_type");
			string rb_connector_dir <- string(rb get "connector_dir");
			float  rb_connector_speed <- float(rb get "connector_speed");

			string emode <- "";
			float  espeed <- 0.0;

			if rb_edge_type = "road" {
				emode  <- walk_mode;
				espeed <- speed_by_mode[walk_mode];
			} else if rb_edge_type = "metro" {
				emode  <- "MTR";
				espeed <- speed_by_mode["MTR"];
			} else if rb_edge_type = "bus" {
				emode  <- "BUS";
				espeed <- speed_by_mode["BUS"];
			} else if rb_connector_dir = "boarding" {
				emode  <- waiting_mode;
				espeed <- rb_connector_speed;
			} else if rb_connector_dir = "alighting" {
				emode  <- "Alighting";
				espeed <- rb_connector_speed;
			} else {
				write "⚠️ Edge type non reconnu pour " + transit_mode + " : edge_type=" + rb_edge_type;
			}

			// Changement of the mode → create a step
			if emode != prev_mode and emode != "" {
				if prev_mode != "" {
					geometry rb_shape <- geometry(rb get "shape");
					do build_step(point(rb_shape.points[0]), prev_mode, prev_speed, false);
					
					if prev_mode != "Alighting"{
						trip_structure <- trip_structure + "-"+prev_mode;
					}
					
				}
				prev_mode  <- emode;
				prev_speed <- espeed;
			}
		}

		do build_step(end_point,prev_mode, prev_speed, false);
		if prev_mode != "Alighting"{
						trip_structure <- trip_structure + "-"+prev_mode;
					}

	}

	// ── save simulation outputs in CSV ─────────────────────────────────────────────────────

	/**
	 * write in two csv files the information at the end of each trip
	 */
	action save_trip_results() {
		float crow_flies_m <- (current_trip != nil and current_trip.origin_point != nil and current_trip.destination_point != nil) ? (current_trip.origin_point distance_to current_trip.destination_point) : 0.0;
		float orig_x <- (current_trip != nil and current_trip.origin_point != nil) ? current_trip.origin_point.x : 0.0;
		float orig_y <- (current_trip != nil and current_trip.origin_point != nil) ? current_trip.origin_point.y : 0.0;
		float dest_x <- (current_trip != nil and current_trip.destination_point != nil) ? current_trip.destination_point.x : 0.0;
		float dest_y <- (current_trip != nil and current_trip.destination_point != nil) ? current_trip.destination_point.y : 0.0;
		save [
			person_id,
			weight_survey,
			current_trip.trip_number,
			current_trip.dep_id,
			mode_utility,
			mode_survey,
			string(time_departure_current_trip),
			string(current_date),
			current_trip.destination_purpose,
			real_trip_duration_min,
			current_trip.duration_minutes,
			real_distance_m,
			crow_flies_m,
			walk_duration_min,
			transit_duration_min,
			waiting_duration_min,
			trip_structure != nil ? trip_structure : "",
			orig_x,
			orig_y,
			dest_x,
			dest_y
		]
		to: results_folder + "trip_durations.csv"
		format: "csv"
		rewrite: false
		header: false;
	}
	
	float get_pt_asc(path p) {
	    // if no path, really low utility
	    if (p = nil or length(p.edges) = 0) { return -100.0; }
	    
	    float dist_bus <- 0.0;
	    float dist_metro <- 0.0;
	    
	    loop e over: p.edges {
	        public_transport edge_agent <- public_transport(e);
	        string type <- string(edge_agent get "edge_type");
	        
	        if (type = "bus") {
	            dist_bus <- dist_bus + e.perimeter;
	        } else if (type = "metro") {
	            dist_metro <- dist_metro + e.perimeter;
	        }
	    }
	    
	    float total_pt_dist <- dist_bus + dist_metro;
	    
	    // if no bus or no metro: just road
	    if (total_pt_dist = 0.0) { return get_asc("bus"); }
	    
	    // mean of ASC
	    return (dist_bus / total_pt_dist) * get_asc("bus") + (dist_metro / total_pt_dist) * get_asc("metro");
	}
	
	
	
	float estimate_time(string m, path p) {
		

	    if (p = nil or length(p) = 0 or p.shape = nil) {return 100000.0; }
	    
	    // direct mode
	    if (m in ["car", "moto", "walk", "bike"]) {
	        float spd <- (m = "car") ? speed_by_mode["CD"] : (
	                       (m = "moto") ? speed_by_mode["SD"] : 
	                       ((m = "bike") ? speed_by_mode["B"] : speed_by_mode["W"]));
			
			float dist <- (m in ["car", "moto"]) ? p.weight : p.shape.perimeter;
	        return (dist / spd) / 60;
	    }

	    // multi-modal
	    bool transit_used <- false;
	    bool possible <- true;
	    public_transport last_public_transport<-nil;
	    float distance_to_first_station <- 10000.0;
	    float full_distance <- 0.0;
	    
	    float duration_total <- 0.0;
	    loop e over: p.edges {
	    	
	        public_transport edge_agent <- public_transport(e); 
	        string type <- string(edge_agent get "edge_type");
	        if not(transit_used){
	        	if type in ["bus","metro"]{
	        		transit_used <- true;
	      			distance_to_first_station <- location distance_to edge_agent;
	        	}
	        }
	        if (type = "road") {
	            duration_total <- duration_total + (e.perimeter / speed_by_mode["W"]);
	            full_distance <- full_distance + e.perimeter;
	        } else if type = "bus" {
	        	last_public_transport <- edge_agent; 
	            duration_total <- duration_total + (e.perimeter / speed_by_mode["BUS"]);
	            full_distance <- full_distance + e.perimeter;
	        } else if (type = "metro"){
	        	last_public_transport <- edge_agent; 
	        	full_distance <- full_distance + e.perimeter;
	            duration_total <- duration_total + (e.perimeter / speed_by_mode["MTR"]);
	        }
	        else if (string(edge_agent get "connector_dir") = "boarding") {
	        	
	            duration_total <- duration_total + float(edge_agent get "weight"); 
	        }
	    }
	    
	    if not(transit_used){	  
	    	current_trip.real_start <- current_start_point;
	    	current_trip.real_end <- current_end_point;
	    	current_trip.display_trip <- true; 	
	    	return 100000.0;
	    }
	    
	    float max_distance_to_walk <- (full_distance > 10000.0) ? min(3.5*1000.0,full_distance *0.2): 2000.0;
	    
	    if distance_to_first_station > max_distance_to_walk
	    		 or (current_trip.destination_point distance_to last_public_transport > max_distance_to_walk) { 
			return 100000.0;
	     }

	    return duration_total /60;
	}
    
    float estimate_cost(string m, path p) {
    	if (p = nil or length(p) = 0 or p.shape = nil) { return 1000000.0; }
//    	price of gas 24 770 VND per litre
	        
    	float dist <- p.shape.perimeter;
        if (m = "metro")  {
        	return 10000.0; // price of the ticket
        } else if (m = "bus" or m="pt"){
        	if bus_subscription = "Oui" {
        		return 0.0;
        	} else {
        		return 10000.0;
        	}
        }else if (m = "car"){
//          ~for car 8 L / 100 km
        	return (dist/1000)*1980.0;
        } else if (m = "moto"){
//        	for moto: ~2,5 L / 100 km
        	return (dist/1000)*620.0;
        }
//        for walk and bike
        return 0.0; 
    }
    
    float get_beta_time() {
        if (current_status in beta_time_by_status.keys) {
            return beta_time_by_status[current_status];
        }
        write "status not recognized: " + current_status;
        return -0.10; // default
	}
	
	float get_beta_cost() {
        if (current_status in beta_cost_by_status.keys) {
            return beta_cost_by_status[current_status];
        }
        write "status not recognized: " + current_status;
        return -0.00005; // default
	}
	
	float get_asc(string mode) {
        if (mode = "moto") { return 0.0; }
        if (current_status in asc_by_status.keys) {
            map<string, float> mode_map <- asc_by_status[current_status];
            if (mode in mode_map.keys) {
                return mode_map[mode];
            }
        }
        write "mode or status not recognized: " + mode + " / " + current_status;
        return 0.0;
	}
	

	// logit multinomial to choose the mode for the trip
	string choose_mode(path car_path, path scooter_path, path bike_path, path walk_path, path b_graph, path m_graph, path pt_graph) {
		bool can_drive_car <- (gas_car + electric_car > 0);
		bool can_drive_moto <- (gas_scooter + electric_scooter > 0);
		bool can_bike <- (manual_bike + electric_bike > 0);	    
		
		float b_time <- get_beta_time();
		float b_cost <- get_beta_cost();

		float time_sd <- ((can_drive_moto ? 0.0 : 5.0) + estimate_time("moto", scooter_path));
		float time_cd <- ((can_drive_car ? 0.0 : 5.0) + estimate_time("car", car_path));
		float time_w  <- estimate_time("walk", walk_path);
		float time_b  <- ((can_bike ? 0.0 : 5.0) + estimate_time("bike", bike_path));
		float time_pt <- multimodal ? estimate_time("pt", pt_graph) : 100000.0;

		float cost_sd <- estimate_cost("moto", scooter_path);
		float cost_cd <- estimate_cost("car", car_path);
		float cost_w  <- estimate_cost("walk", walk_path);
		float cost_b  <- estimate_cost("bike", bike_path);
		float cost_pt <- multimodal ? estimate_cost("pt", pt_graph) : 0.0;

		// 1. compute utility term V (V = ASC + B_time * T + B_cost * C)
		float v_moto <- get_asc("moto") + (b_time * time_sd) + (b_cost * cost_sd);
		float v_car  <- get_asc("car")  + (b_time * time_cd) + (b_cost * cost_cd);
		float v_walk <- get_asc("walk") + (b_time * time_w)  + (b_cost * cost_w);
		float v_bike <- get_asc("bike") + (b_time * time_b)  + (b_cost * cost_b);
        
		// 2. U = V + epsilon
		float u_moto <- v_moto + eps_terms["SD"];
		float u_car  <- v_car  + eps_terms["CD"];
		float u_walk <- v_walk + eps_terms["W"];
		float u_bike <- v_bike + eps_terms["B"];
        
		map<string, float> utilities <- [];
		if multimodal {
			float asc_pt_dynamic <- get_pt_asc(pt_graph);
			float v_pt <- asc_pt_dynamic + (b_time * time_pt) + (b_cost * cost_pt);
			float u_pt <- v_pt + eps_terms["PT"];
			utilities <- [
				"SD"::u_moto,
				"CD"::u_car,
				"PT"::u_pt,
				"W"::u_walk,
				"B"::u_bike
			];
		} else {
			float v_metro <- get_asc("metro") + (b_time * estimate_time("metro", m_graph)) + (b_cost * estimate_cost("metro", m_graph));
			float v_bus <- get_asc("bus") + (b_time * estimate_time("bus", b_graph)) + (b_cost * estimate_cost("bus", b_graph));
			float u_metro <- v_metro + eps_terms["MTR"];     
			float u_bus <- v_bus + eps_terms["BUS"];
			utilities <- [
				"SD"::u_moto,
				"CD"::u_car,
				"MTR"::u_metro,
				"BUS"::u_bus,
				"W"::u_walk,
				"B"::u_bike
			];
		}
        
		if (max(utilities.values) < -10000.0) {
			path fallback_path <- path_between(world_topology_graph, location, target);
			v_moto <- get_asc("moto") + ((b_time * ((can_drive_moto ? 0.0 : 5.0) + estimate_time("moto", fallback_path))) + (b_cost * estimate_cost("moto", fallback_path)));
			v_car  <- get_asc("car")  + ((b_time * ((can_drive_car ? 0.0 : 5.0)  + estimate_time("car", fallback_path)))  + (b_cost * estimate_cost("car", fallback_path)));
			v_walk <- get_asc("walk") + (b_time * estimate_time("walk", fallback_path)) + (b_cost * estimate_cost("walk", fallback_path));
			v_bike <- get_asc("bike") + ((b_time * ((can_bike ? 0.0 : 5.0)       + estimate_time("bike", fallback_path))) + (b_cost * estimate_cost("bike", fallback_path)));
			utilities <- [
				"SD":: v_moto + eps_terms["SD"],
				"CD":: v_car + eps_terms["CD"],
				"W":: v_walk + eps_terms["W"],
				"B":: v_bike + eps_terms["B"]
			];
		}
		return utilities.keys[utilities.values index_of max(utilities.values)];
	}

	/**
	 * Estimates the average traffic density along the corridor between p_start and p_end
	 * by sampling the continuous raster heatmap every 150 meters.
	 */
	float estimate_corridor_density(point p_start, point p_end) {
		if (!apply_congestion) { return 0.0; }
		float dist <- p_start distance_to p_end;
		if (dist <= 300.0) {
			return float(instant_heatmap[(p_start + p_end) / 2.0]);
		}
		// Sample 3 key points (25%, 50%, 75%) along the corridor for O(1) performance
		point p1 <- p_start + (p_end - p_start) * 0.25;
		point p2 <- (p_start + p_end) * 0.50;
		point p3 <- p_start + (p_end - p_start) * 0.75;
		return (float(instant_heatmap[p1]) + float(instant_heatmap[p2]) + float(instant_heatmap[p3])) / 3.0;
	}

	/**
	 * Computes the Multimodal Logsum Accessibility measure A(a_i, target_pt) to any target location:
	 * A(a_i, target_pt) = ln( sum_{m in M_i} exp( V_m(a_i, target_pt) ) )
	 * Factorized across modes using empirical detour factors and 150m corridor congestion sampling.
	 */
	float compute_accessibility_to_point(point target_pt) {
		if (target_pt = nil) { return -100.0; }
		
		float crow_flies_dist <- location distance_to target_pt;
		if (crow_flies_dist <= 0.0) { return 0.0; }
		
		// 1. Dynamic congestion factors along 150m corridor
		float corridor_density <- estimate_corridor_density(location, target_pt);
		float cong_car     <- 1.0 - min(max_slowdown_car, corridor_density / max_congestion_density);
		float cong_scooter <- 1.0 - min(max_slowdown_factor, corridor_density / max_congestion_density);
		
		float beta_t <- get_beta_time();
		float beta_c <- get_beta_cost();
		
		// 2. Mode specifications: [detour, speed, penalty_min, cost_per_km, flat_cost]
		map<string, list<float>> mode_specs <- [
			"walk":: [detour_factors["W"],  speed_by_mode["W"],                0.0,                                             0.0,    0.0],
			"bike":: [detour_factors["B"],  speed_by_mode["B"] * cong_scooter, (manual_bike + electric_bike > 0 ? 0.0 : 5.0),   0.0,    0.0],
			"moto":: [detour_factors["SD"], speed_by_mode["SD"] * cong_scooter,(gas_scooter + electric_scooter > 0 ? 0.0 : 5.0),620.0, 0.0],
			"car" :: [detour_factors["CD"], speed_by_mode["CD"] * cong_car,    (gas_car + electric_car > 0 ? 0.0 : 5.0),       1980.0, 0.0],
			"bus" :: [detour_factors["PT"], speed_by_mode["BUS"] * cong_car,   5.0,                                             0.0,    (bus_subscription = "Oui" ? 0.0 : 10000.0)]
		];
		
		// 3. Compute systematic utilities across all modes
		list<float> v_list <- [];
		loop m over: mode_specs.keys {
			list<float> spec <- mode_specs[m];
			float d <- crow_flies_dist * spec[0];
			float t <- ((d / max(0.5, spec[1])) / 60.0) + spec[2];
			float c <- (d / 1000.0) * spec[3] + spec[4];
			add (get_asc(m) + beta_t * t + beta_c * c) to: v_list;
		}
		
		// 4. Numerically stable LogSum: max_v + ln(sum(exp(v - max_v)))
		float max_v <- max(v_list);
		float sum_exp <- 0.0;
		loop v over: v_list {
			sum_exp <- sum_exp + exp(v - max_v);
		}
		return max_v + ln(sum_exp);
	}

	float compute_multimodal_logsum_accessibility(affordance_cell cell) {
		if (cell = nil) { return -100.0; }
		return compute_accessibility_to_point(cell.location);
	}
	
	// Helper action to sample activity duration [min, max] according to CSP and purpose
	list<int> get_activity_duration_range(string status, string purpose) {
		if (status in activity_duration_by_status.keys) {
			map<string, list<int>> purp_map <- activity_duration_by_status[status];
			if (purpose in purp_map.keys) {
				return purp_map[purpose];
			}
		}
		// Fallback default if status not matched
		return (purpose = "Shop") ? [20, 60] : [30, 90];
	}

	// Helper action to sample activity duration (min) via Log-Normal distribution or interval
	float sample_activity_duration(string status, string purpose) {
		float dur <- 45.0;
		if (activity_duration_model = "distribution" and (purpose in activity_lognormal_params.keys)) {
			map<string, list<float>> p_map <- activity_lognormal_params[purpose];
			list<float> params <- (status in p_map.keys) ? p_map[status] : p_map["Actif"];
			dur <- exp(gauss(params[0], params[1]));
		} else {
			list<int> dur_range <- get_activity_duration_range(status, purpose);
			dur <- float(rnd(dur_range[0], dur_range[1]));
		}
		// Evening time-budget tapering: evening grocery/retail stops (Shop: 15-65 min) vs evening dining/socializing (Others: 25-120 min)
		float cur_h <- current_date.hour + (current_date.minute / 60.0);
		if (purpose = "Shop" and cur_h >= 16.5) {
			return max(15.0, min(65.0, dur * 0.85));
		} else if (purpose = "Others" and cur_h >= 17.5) {
			return max(25.0, min(120.0, dur * 0.90));
		}
		return max(5.0, min(240.0, dur));
	}

	// ── Step 9: Autonomous Activity Agenda Actions ──────────────────────────

	// Dynamically create a trip agent for the autonomous activity agenda
	action create_autonomous_trip(point dest_pt, string dest_purp, string orig_purp) {
		if (dest_pt = nil) { return; }
		// When leaving Home: after a midday meal hunger is 0.0; on first morning departure, workers have eaten breakfast (hunger 0.0); slight variation for students [0.0, 0.16] reproduces early morning recess (~09h45-10h30)
		if (orig_purp = "Home") {
			internal_needs["hunger"] <- morning_commute_done ? 0.0 : ((current_status = "Actif") ? 0.0 : rnd(0.0, 0.16));
		}
		num_trip <- num_trip + 1;
		create trip {
			trip_number <- myself.num_trip * 1000 + myself.person_id;
			person_id <- myself.person_id;
			dep_id <- myself.num_trip;
			origin_purpose <- orig_purp;
			destination_purpose <- dest_purp;
			origin_point <- myself.location;
			destination_point <- dest_pt;
			departure_time <- current_date;
			main_mode <- "SD";
			myself.current_trip <- self;
		}
		agenda_state <- "Commuting";
	}

	// Initializes only the mandatory anchor schedule (departure & duration); all breaks and secondary activities emerge from needs vs affordances
	action init_autonomous_schedule() {
		if (!generate_activities or schedule_initialized) { return; }
		schedule_initialized <- true;
		
		int sim_year <- starting_date.year;
		int sim_month <- starting_date.month;
		int sim_day <- starting_date.day;

		// 1. Identify school escort status: adults aged > 24 with child school assigned (92.4% in survey do short drop-offs, whereas Actif aged <= 24 are young working students/apprentices)
		bool is_young_working_student <- (current_status = "Actif" and age <= 24 and education_location != nil);
		is_school_escort <- (current_status != "Étudiant ou élève" and !is_young_working_student and education_location != nil);
		if (is_school_escort) {
			float escort_h <- max(6.5, min(8.5, gauss(escort_dep_mean_hour, escort_dep_std_hour)));
			int eh_hour <- int(escort_h);
			int eh_min <- int((escort_h - eh_hour) * 60);
			escort_dropoff_time <- date([sim_year, sim_month, sim_day, eh_hour, eh_min, 0]);
			
			float pickup_h <- max(15.5, min(18.0, gauss(escort_pickup_mean_hour, escort_pickup_std_hour)));
			int ph_hour <- int(pickup_h);
			int ph_min <- int((pickup_h - ph_hour) * 60);
			escort_pickup_time <- date([sim_year, sim_month, sim_day, ph_hour, ph_min, 0]);
		}

		// 2. Schedule mandatory anchor for Students & Young Working Students/Apprentices (N=721 true students in survey, excluding adult Escorts & subtracting breaks):
		// - 16.9% Afternoon-Only (dep 13h08, net median 200.5 min -> LogNormal mu=5.298, sigma=0.412, no midday break)
		// - 47.0% Morning-Only (56.6% of morning departures, dep 07h08, net median 270 min -> LogNormal mu=5.445, sigma=0.332, no midday break, exit ~11h45 -> H-E-H)
		// - 36.1% Full-Day (43.4% of morning departures, dep 07h22, net study median 474 min with breaks removed -> LogNormal mu=6.098, sigma=0.296, 36.9% take external lunch break)
		if (((current_status = "Étudiant ou élève" or is_young_working_student) and education_location != nil) or (education_location != nil and work_location = nil and !is_school_escort)) {
			bool is_dual_anchor <- ((current_status = "Étudiant ou élève" or is_young_working_student) and education_location != nil and work_location != nil);
			bool afternoon_shift <- (!is_dual_anchor and flip(prob_student_afternoon_shift));
			float dep_h <- afternoon_shift ? 
				max(11.5, min(14.5, gauss(edu_afternoon_dep_mean_hour, edu_afternoon_dep_std_hour))) :
				max(5.5, min(10.0, gauss(edu_dep_mean_hour, edu_dep_std_hour)));
			int dh_hour <- int(dep_h);
			int dh_min <- int((dep_h - dh_hour) * 60);
			morning_dep_time <- date([sim_year, sim_month, sim_day, dh_hour, dh_min, 0]);

			float dur_raw <- 270.0;
			if (is_dual_anchor) {
				// Survey empirical split for 80 dual-anchor students:
				// - 19% morning job shift (work 07h30-11h45 -> afternoon study 12h30-16h30) -> reproduces H-W-E-H & H-W-H-E-H
				// - 61% afternoon job shift (morning study 07h15-11h35 -> home lunch / transit -> work 12h30-16h30) -> reproduces H-E-H-W-H (28) & H-E-W-H (14)
				// - 20% evening job shift (full-day study 07h15-16h45 -> evening tutoring/hospitality job 17h00-21h00)
				float r_dual <- rnd(1.0);
				if (r_dual < 0.19) {
					has_morning_student_job <- true;
					has_afternoon_student_job <- false;
					has_evening_student_job <- false;
					float dep_hw <- max(6.0, min(8.5, gauss(work_dep_mean_hour, work_dep_std_hour)));
					int dh_hour_w <- int(dep_hw);
					int dh_min_w <- int((dep_hw - dh_hour_w) * 60);
					morning_dep_time <- date([sim_year, sim_month, sim_day, dh_hour_w, dh_min_w, 0]);
					dur_raw <- max(180.0, min(270.0, (11.75 - dep_hw) * 60.0 + gauss(0.0, 10.0)));
				} else if (r_dual < 0.65) {
					has_morning_student_job <- false;
					has_afternoon_student_job <- true;
					has_evening_student_job <- false;
					dur_raw <- max(180.0, min(300.0, (11.35 - dep_h) * 60.0 + gauss(0.0, 10.0)));
				} else {
					has_morning_student_job <- false;
					has_afternoon_student_job <- false;
					has_evening_student_job <- true;
					dur_raw <- max(180.0, min(300.0, (11.35 - dep_h) * 60.0 + gauss(0.0, 10.0)));
				}
			} else if (afternoon_shift) {
				// 3. Afternoon-Only regime (16.9%): Log-Normal(5.298, 0.412) net of breaks (median 200.5 min = 3.34h), capped so class finishes before 17:30
				dur_raw <- max(120.0, min(max(150.0, (17.35 - dep_h) * 60.0), exp(gauss(edu_afternoon_lognormal_mu, edu_afternoon_lognormal_sigma))));
				break_taken_today <- true;
			} else if (flip(prob_student_morning_halfday)) {
				// 1. Morning-Only regime (47.0% of all students): empirical school bell rings at 11h35-11h40 (survey median 11h39, travel added -> restores sharp 11h45 transit peak)
				dur_raw <- max(180.0, min(300.0, (11.35 - dep_h) * 60.0 + gauss(0.0, 12.0)));
				break_taken_today <- true;
			} else {
				// 2. Full-Day regime (36.1% of all students): Log-Normal(6.098, 0.296) net of breaks (median 474 min = 7.90h net study + ~55m lunch break -> exit ~16h30)
				dur_raw <- max(330.0, min(560.0, exp(gauss(edu_fullday_lognormal_mu, edu_fullday_lognormal_sigma))));
			}
			mandatory_duration_min <- dur_raw;
			remaining_mandatory_min <- mandatory_duration_min;
		}
		// 3. Schedule mandatory anchor for Workers and Interns/Working Students with Work anchor only
		else if (work_location != nil) {
			// Empirical survey profile: 11.5% afternoon shift among young (<=25) or older (>50) workers vs 3.5% among prime-age (25-50) workers (overall 6.5% = 54/834)
			float p_late <- (age <= 25 or age > 50) ? 0.115 : 0.035;
			bool afternoon_shift <- flip(p_late);
			float dep_h <- afternoon_shift ?
				max(11.5, min(16.5, gauss(work_afternoon_dep_mean_hour, work_afternoon_dep_std_hour))) :
				max(5.5, min(11.0, gauss(work_dep_mean_hour, work_dep_std_hour)));
			int dh_hour <- int(dep_h);
			int dh_min <- int((dep_h - dh_hour) * 60);
			morning_dep_time <- date([sim_year, sim_month, sim_day, dh_hour, dh_min, 0]);
			
			if (afternoon_shift) {
				// Afternoon/evening shift (median 280-291 min = 4.75h, no midday lunch break)
				float dur_raw <- exp(gauss(work_late_duration_lognormal_mu, work_late_duration_lognormal_sigma));
				mandatory_duration_min <- max(120.0, min(420.0, dur_raw));
				remaining_mandatory_min <- mandatory_duration_min;
				break_taken_today <- true;
			} else {
				// If student apprentice: morning half-day shift (median 260 min, ending ~11h45)
				// If regular worker: Standard full-day shift: Log-Normal(6.059, 0.285) net of breaks (median 454 min = 7.57h net work + ~58m lunch break -> exit ~17h30)
				float dur_raw <- (current_status = "Étudiant ou élève") ?
					max(180.0, min(330.0, (11.45 - dep_h) * 60.0 + gauss(0.0, 15.0))) :
					exp(gauss(work_duration_lognormal_mu, work_duration_lognormal_sigma));
				mandatory_duration_min <- (current_status = "Étudiant ou élève") ? dur_raw : max(180.0, min(660.0, dur_raw));
				remaining_mandatory_min <- mandatory_duration_min;
			}
		}
		// 4. Set initial base state
		agenda_state <- "At_Home";
		current_activity <- "Home";
		if (home_location != nil) {
			location <- home_location;
		}
	}

	// ── Reflexes ─────────────────────────────────────────────────────────────

	reflex accumulate_internal_needs when: generate_activities {
		// Decrement remaining mandatory work/study duration ONLY while actively working/studying (including external business errands, paused during breaks & travel!)
		if (agenda_state = "At_Mandatory" and !is_on_break and target = nil and current_trip = nil) {
			remaining_mandatory_min <- max(0.0, remaining_mandatory_min - (step / 60.0));
		}
		
		// Circadian biological rest rhythm: metabolic attenuation during nocturnal sleep hours (23:00 to 06:00)
		float circadien_factor <- (current_date.hour >= 23 or current_date.hour < 6) ? night_metabolic_factor : 1.0;
		float dt_hours <- (step / 3600.0) * circadien_factor;
		bool at_mandatory <- (agenda_state = "At_Mandatory" or current_activity in ["Work", "Education"]);
		// Actifs without a fixed workplace operate as home-based agents (teleworkers/freelancers/craftsmen) with homemaker activity dynamics
		string effective_status <- (current_status = "Actif" and work_location = nil) ? "Personne au foyer" : current_status;
		map<string, float> rates <- lambda_need_rates_by_status[effective_status];
		if (rates = nil) {
			rates <- lambda_need_rates_by_status["Actif"];
		}
		loop need_key over: internal_needs.keys {
			// Pause accumulation of the need currently being satisfied on a break or discretionary activity
			if (activity_end_time != nil and active_satisfied_need = need_key) {
				continue;
			}
			// While at Home before morning departure, 90% of commuting agents have breakfast at home so hunger stays at 0.0
			// 10% can experience morning hunger/leisure to allow pre-commute street food / café stops (H -> O -> W)
			if (need_key = "hunger" and agenda_state = "At_Home" and morning_dep_time != nil and !morning_commute_done and (int(self) mod 10 != 0)) {
				internal_needs["hunger"] <- 0.0;
				continue;
			}
			if (need_key in rates.keys) {
				internal_needs[need_key] <- min(1.0, internal_needs[need_key] + rates[need_key] * dt_hours);
			}
		}
	}

	// ── Survey Trip Replay (Only active when generate_activities is false) ──
	reflex selectNextTrip when: (!generate_activities and num_trip < length(trips) and current_trip = nil and activity_end_time = nil) {
		current_trip <- trips[num_trip];
		color <- rgb(mode_color[current_trip.main_mode].red, mode_color[current_trip.main_mode].green, mode_color[current_trip.main_mode].blue, 0.1);
		num_trip <- num_trip + 1;
	}

	// ── Step 9.1: Autonomous Morning Mandatory Commute Trigger ──────────────
	reflex trigger_autonomous_morning_commute when: generate_activities and agenda_state = "At_Home" and target = nil and current_trip = nil and activity_end_time = nil {
		// 1. School escort morning drop-off
		if (is_school_escort and escort_stage = 0 and escort_dropoff_time != nil and current_date >= escort_dropoff_time) {
			do create_autonomous_trip(education_location, "Escort", "Home");
			return;
		}
		
		// 2. Worker or Student morning mandatory commute (supports cross-status working students & adult trainees)
		if (morning_dep_time != nil and !morning_commute_done and current_date >= morning_dep_time) {
			bool is_young_ws <- (current_status = "Actif" and age <= 24 and education_location != nil);
			if (has_morning_student_job and work_location != nil) {
				do create_autonomous_trip(work_location, "Work", "Home");
				morning_commute_done <- true;
			} else if (((current_status = "Étudiant ou élève" or is_young_ws) and education_location != nil) or (education_location != nil and work_location = nil and !is_school_escort)) {
				do create_autonomous_trip(education_location, "Education", "Home");
				morning_commute_done <- true;
			} else if (work_location != nil) {
				do create_autonomous_trip(work_location, "Work", "Home");
				morning_commute_done <- true;
			}
		}
	}

	reflex trigger_afternoon_school_escort when: generate_activities and is_school_escort and escort_stage = 1 and escort_pickup_time != nil and current_date >= escort_pickup_time and target = nil and current_trip = nil and activity_end_time = nil and !is_on_break {
		do create_autonomous_trip(education_location, "Escort", current_activity);
	}

	reflex complete_escort_stop when: generate_activities and current_activity = "Escort" and activity_end_time != nil and current_date >= activity_end_time and target = nil and current_trip = nil {
		activity_end_time <- nil;
		if (escort_stage = 0) {
			// Morning drop-off completed
			escort_stage <- 1;
			if (current_status = "Actif" and work_location != nil) {
				do create_autonomous_trip(work_location, "Work", "Escort");
				morning_commute_done <- true;
			} else {
				do create_autonomous_trip(home_location, "Home", "Escort");
				morning_commute_done <- true;
			}
		} else if (escort_stage = 1) {
			// Afternoon pick-up completed: return home
			escort_stage <- 2;
			do create_autonomous_trip(home_location, "Home", "Escort");
			evening_return_done <- true;
		}
	}

	reflex evaluate_midday_affordance when: generate_activities and agenda_state = "At_Mandatory" and !is_on_break and !is_business_errand and !break_taken_today and target = nil and current_trip = nil and activity_end_time = nil and (next_affordance_eval_time = nil or current_date >= next_affordance_eval_time) {
		// Only take a midday break if on a full-day schedule (at least 120 min of afternoon commitment remaining, and >= 300 min total for students so half-day morning students exit at 11h45 -> Home)
		if (remaining_mandatory_min < 120.0 or (current_activity = "Education" and mandatory_duration_min < 300.0)) {
			return;
		}
		
		// 1. Evaluate midday meal break when biological "hunger" crosses threshold tau_hunger (preserving "shop" and "leisure" needs for after-work/after-school outings at 16h-19h30)
		string active_need <- "";
		if (internal_needs["hunger"] >= tau_need_thresholds["hunger"]) {
			active_need <- "hunger";
		}
		if (active_need = "") {
			next_affordance_eval_time <- current_date + 15 #minute;
			return;
		}
		
		float radius <- (active_need in need_perception_radius.keys) ? need_perception_radius[active_need] : midday_perception_radius;
		list<affordance_cell> near_cells <- (affordance_cell at_distance radius) where (location distance_to each.location <= radius);
		list<string> eligible_pois <- (active_need in need_eligible_poi_types.keys) ? need_eligible_poi_types[active_need] : ["Others", "Shop"];
		
		map<affordance_cell, float> others_utils <- [];
		map<affordance_cell, float> shop_utils <- [];
		
		loop c over: near_cells {
			float cell_acc <- 0.0;
			bool acc_computed <- false;
			
			if ("Others" in eligible_pois and c.is_open("Others", current_date.hour) and c.get_remaining_capacity("Others") > 0 and !empty(c.poi_locations["Others"])) {
				cell_acc <- compute_multimodal_logsum_accessibility(c);
				acc_computed <- true;
				others_utils[c] <- (need_weight * internal_needs[active_need]) +
				                   (attractiveness_weight * c.poi_attractiveness["Others"]) -
				                   (crowding_weight * c.get_occupancy_ratio("Others")) +
				                   (accessibility_weight * cell_acc);
			}
			if ("Shop" in eligible_pois and c.is_open("Shop", current_date.hour) and c.get_remaining_capacity("Shop") > 0 and !empty(c.poi_locations["Shop"])) {
				if (!acc_computed) {
					cell_acc <- compute_multimodal_logsum_accessibility(c);
				}
				shop_utils[c] <- (need_weight * internal_needs[active_need]) +
				                 (attractiveness_weight * c.poi_attractiveness["Shop"]) -
				                 (crowding_weight * c.get_occupancy_ratio("Shop")) +
				                 (accessibility_weight * cell_acc) -
				                 (active_need = "hunger" ? hunger_shop_penalty : 0.0);
			}
		}
		
		affordance_cell chosen_others_cell <- nil;
		float u_others_rep <- -100000.0;
		if (!empty(others_utils)) {
			float max_uo <- max(others_utils.values);
			map<affordance_cell, float> others_probs <- [];
			loop c over: others_utils.keys {
				others_probs[c] <- exp(others_utils[c] - max_uo);
			}
			chosen_others_cell <- rnd_choice(others_probs);
			if (chosen_others_cell != nil) {
				u_others_rep <- others_utils[chosen_others_cell];
			}
		}
		
		affordance_cell chosen_shop_cell <- nil;
		float u_shop_rep <- -100000.0;
		if (!empty(shop_utils)) {
			float max_us <- max(shop_utils.values);
			map<affordance_cell, float> shop_probs <- [];
			loop c over: shop_utils.keys {
				shop_probs[c] <- exp(shop_utils[c] - max_us);
			}
			chosen_shop_cell <- rnd_choice(shop_probs);
			if (chosen_shop_cell != nil) {
				u_shop_rep <- shop_utils[chosen_shop_cell];
			}
		}
		
		// 3. Step B (Macro 4-Option MNL): Fair 1-vs-1-vs-1-vs-1 competition between [Stay, Home, Others, Shop]
		map<string, float> option_utilities <- [];
		
		// Option 1: Stay on-site (workplace/school canteen, lunchbox, or deferring non-urgent outing)
		map<string, float> stay_map <- (current_activity = "Work") ? stay_on_site_utility_work : stay_on_site_utility_edu;
		option_utilities["Stay"] <- (need_weight * internal_needs[active_need]) + stay_map[active_need];
		
		// Option 2: Return Home for meal (when active_need = "hunger" and within space-time prism)
		if (active_need = "hunger" and home_location != nil and (location distance_to home_location) <= midday_home_max_dist) {
			option_utilities["Home"] <- (need_weight * internal_needs["hunger"]) +
			                            midday_home_lunch_utility +
			                            (accessibility_weight * compute_accessibility_to_point(home_location));
		}
		
		// Option 3: Best/chosen "Others" cell (restaurant / cafe / leisure)
		if (chosen_others_cell != nil) {
			option_utilities["Others"] <- u_others_rep;
		}
		
		// Option 4: Best/chosen "Shop" cell (bakery / grocery / retail)
		if (chosen_shop_cell != nil) {
			option_utilities["Shop"] <- u_shop_rep;
		}
		
		float max_u <- max(option_utilities.values);
		map<string, float> option_probs <- [];
		loop opt over: option_utilities.keys {
			option_probs[opt] <- exp(option_utilities[opt] - max_u);
		}
		string chosen_option <- rnd_choice(option_probs);
		if (chosen_option = nil or chosen_option = "") {
			next_affordance_eval_time <- current_date + 20 #minute;
			return;
		}
		
		// 4. Execute chosen affordance among [Stay, Home, Others, Shop]
		if (chosen_option = "Stay") {
			if (active_need = "hunger") {
				internal_needs["hunger"] <- 0.0;
				// On-site lunch break at Work/Education: pauses remaining_mandatory_min for ~55 min without creating an external trip!
				is_on_break <- true;
				agenda_state <- "At_Midday_Break";
				active_satisfied_need <- "hunger";
				affordance_origin_location <- location;
				affordance_origin_activity <- current_activity;
				float onsite_dur <- max(35.0, min(110.0, gauss(onsite_lunch_duration_mean_min, onsite_lunch_duration_std_min)));
				activity_end_time <- current_date + (int(onsite_dur * 60) #sec);
			} else {
				internal_needs[active_need] <- max(0.0, tau_need_thresholds[active_need] - 0.10);
				next_affordance_eval_time <- current_date + 45 #minute;
			}
			return;
		}
		
		if (chosen_option = "Home") {
			is_on_break <- true;
			active_satisfied_need <- active_need;
			affordance_origin_location <- location;
			affordance_origin_activity <- current_activity;
			do create_autonomous_trip(home_location, "Home", current_activity);
			return;
		}
		
		affordance_cell target_cell <- (chosen_option = "Others") ? chosen_others_cell : chosen_shop_cell;
		if (target_cell != nil and target_cell.reserve_slot(chosen_option)) {
			is_on_break <- true;
			active_satisfied_need <- active_need;
			current_affordance_cell <- target_cell;
			affordance_origin_location <- location;
			affordance_origin_activity <- current_activity;
			point dest_poi <- target_cell.get_random_poi_location(chosen_option);
			do create_autonomous_trip(dest_poi, chosen_option, current_activity);
		} else {
			next_affordance_eval_time <- current_date + 20 #minute;
		}
	}

	// ── Step 9.3: Complete Emergent Break (On-Site or External) & Resume Mandatory Anchor ───
	reflex complete_midday_break when: generate_activities and agenda_state = "At_Midday_Break" and activity_end_time != nil and current_date >= activity_end_time and target = nil and current_trip = nil {
		if (current_affordance_cell != nil) {
			current_affordance_cell.release_slot(current_activity);
			current_affordance_cell <- nil;
		}
		if (active_satisfied_need != "" and active_satisfied_need in internal_needs.keys) {
			internal_needs[active_satisfied_need] <- 0.0;
		} else {
			internal_needs["hunger"] <- 0.0;
		}
		active_satisfied_need <- "";
		activity_end_time <- nil;
		
		point return_target <- (affordance_origin_location != nil) ? affordance_origin_location : ((work_location != nil) ? work_location : education_location);
		string return_purp  <- (affordance_origin_activity != nil and affordance_origin_activity != "") ? affordance_origin_activity : ((work_location != nil) ? "Work" : "Education");
		
		// If a working student completed their break after morning classes, transition directly to their afternoon or evening Work anchor
		if ((has_afternoon_student_job or has_evening_student_job) and work_location != nil) {
			has_afternoon_student_job <- false;
			has_evening_student_job <- false;
			return_target <- work_location;
			return_purp <- "Work";
			float dur_raw <- exp(gauss(work_late_duration_lognormal_mu, work_late_duration_lognormal_sigma));
			mandatory_duration_min <- max(210.0, min(360.0, dur_raw));
			remaining_mandatory_min <- mandatory_duration_min;
		}
		
		is_on_break <- false;
		break_taken_today <- true;
		
		// If break was taken on-site ("Stay"), resume work/study immediately on-site without generating a trip
		if (location distance_to return_target <= 50.0) {
			current_activity <- return_purp;
			agenda_state <- "At_Mandatory";
			if (remaining_mandatory_min < 45.0) {
				remaining_mandatory_min <- 45.0;
			}
		} else {
			do create_autonomous_trip(return_target, return_purp, current_activity);
		}
		affordance_origin_location <- nil;
		affordance_origin_activity <- "Home";
	}

	// ── Step 9.3: Evening Shift Release, On-Route Detours & Automatic Return Home ───
	reflex trigger_evening_return_and_detour when: generate_activities and agenda_state = "At_Mandatory" and !is_on_break and !is_business_errand and morning_commute_done and !evening_return_done and target = nil and current_trip = nil and activity_end_time = nil {
		bool shift_done <- (remaining_mandatory_min <= 0.0);
		if (!shift_done) { return; }
		
		// 0. Morning working student: finishes morning work shift at ~11h45, commutes to afternoon classes at education_location
		if (has_morning_student_job and current_activity = "Work" and education_location != nil) {
			has_morning_student_job <- false;
			float dur_raw <- max(180.0, min(300.0, exp(gauss(edu_afternoon_lognormal_mu, edu_afternoon_lognormal_sigma))));
			mandatory_duration_min <- dur_raw;
			remaining_mandatory_min <- mandatory_duration_min;
			break_taken_today <- true;
			do create_autonomous_trip(education_location, "Education", "Work");
			return;
		}
		
		// 0a. Afternoon working student: finishes morning classes at ~11h35, takes lunch break until 12h30-13h15, then commutes to afternoon Work shift
		// 0a. Afternoon or Evening working student: finishes morning classes at ~11h35, takes midday break, then commutes to afternoon or evening Work shift
		if ((has_afternoon_student_job or has_evening_student_job) and current_activity = "Education" and work_location != nil) {
			float curr_h <- current_date.hour + current_date.minute / 60.0;
			float target_job_dep_h <- has_afternoon_student_job ? 12.75 : gauss(16.35, 0.35);
			if (curr_h < (target_job_dep_h + 0.25)) {
				is_on_break <- true;
				agenda_state <- "At_Midday_Break";
				active_satisfied_need <- "hunger";
				internal_needs["hunger"] <- 0.0;
				affordance_origin_location <- work_location;
				affordance_origin_activity <- "Work";
				
				// Return Home for lunch/rest if within space-time prism (<= midday_home_max_dist) -> produces empirical H-E-H-W-H
				float base_u_h <- stay_at_home_utility["hunger"];
				float u_home <- (home_location != nil and (location distance_to home_location) <= midday_home_max_dist) ? 
					(base_u_h + (accessibility_weight * compute_accessibility_to_point(home_location))) : -100.0;
				float u_stay <- (stay_on_site_utility_edu["hunger"] - 0.95);
				map<string, float> split_probs <- [
					"Home":: exp(u_home - max(u_home, u_stay)),
					"Stay":: exp(u_stay - max(u_home, u_stay))
				];
				if (rnd_choice(split_probs) = "Home") {
					do create_autonomous_trip(home_location, "Home", "Education");
				} else {
					float onsite_dur <- max(35.0, min(300.0, (target_job_dep_h - curr_h) * 60.0));
					activity_end_time <- current_date + (int(onsite_dur * 60) #sec);
				}
				return;
			}
			has_afternoon_student_job <- false;
			has_evening_student_job <- false;
			float dur_raw <- exp(gauss(work_late_duration_lognormal_mu, work_late_duration_lognormal_sigma));
			mandatory_duration_min <- max(210.0, min(360.0, dur_raw));
			remaining_mandatory_min <- mandatory_duration_min;
			break_taken_today <- true;
			do create_autonomous_trip(work_location, "Work", current_activity);
			return;
		}
		
		// 1. Check school escort afternoon pick-up
		if (is_school_escort and escort_stage = 1) {
			if (current_date >= escort_pickup_time) {
				do create_autonomous_trip(education_location, "Escort", current_activity);
				return;
			}
		}
		
		// 2. Check if any internal need ("shop", "leisure", "hunger") warrants an on-route detour before going Home
		bool has_shop_need <- (internal_needs["shop"] >= tau_need_thresholds["shop"]);
		bool has_oth_need  <- (internal_needs["leisure"] >= tau_need_thresholds["leisure"] or internal_needs["hunger"] >= tau_need_thresholds["hunger"]);
		
		if (has_shop_need or has_oth_need) {
			float radius <- 3500.0;
			list<affordance_cell> near_cells <- (affordance_cell at_distance radius) where (location distance_to each.location <= radius);
			
			map<affordance_cell, float> others_utils <- [];
			map<affordance_cell, float> shop_utils <- [];
			
			loop c over: near_cells {
				float cell_acc <- 0.0;
				bool acc_computed <- false;
				if (has_oth_need and c.is_open("Others", current_date.hour) and c.get_remaining_capacity("Others") > 0 and !empty(c.poi_locations["Others"])) {
					cell_acc <- compute_multimodal_logsum_accessibility(c);
					acc_computed <- true;
					float oth_need_val <- max(internal_needs["leisure"], internal_needs["hunger"]);
					others_utils[c] <- (need_weight * oth_need_val) +
					                   (attractiveness_weight * c.poi_attractiveness["Others"]) -
					                   (crowding_weight * c.get_occupancy_ratio("Others")) +
					                   (accessibility_weight * cell_acc);
				}
				if (has_shop_need and c.is_open("Shop", current_date.hour) and c.get_remaining_capacity("Shop") > 0 and !empty(c.poi_locations["Shop"])) {
					if (!acc_computed) {
						cell_acc <- compute_multimodal_logsum_accessibility(c);
					}
					shop_utils[c] <- (need_weight * internal_needs["shop"]) +
					                 (attractiveness_weight * c.poi_attractiveness["Shop"]) -
					                 (crowding_weight * c.get_occupancy_ratio("Shop")) +
					                 (accessibility_weight * cell_acc);
				}
			}
			
			map<string, float> d_utilities <- [];
			map<string, affordance_cell> d_cell <- [];
			
			// Option 1: Direct return Home (natural domestic utility: dinner / rest at home)
			if (home_location != nil) {
				float u_home_base <- 0.0;
				float home_need_val <- 0.0;
				if (has_oth_need) {
					u_home_base <- (current_status = "Actif") ? 5.30 : ((current_status = "Étudiant ou élève") ? 4.15 : 4.80);
					home_need_val <- max(internal_needs["hunger"], internal_needs["leisure"]);
				} else {
					u_home_base <- stay_at_home_utility["shop"];
					home_need_val <- internal_needs["shop"];
				}
				d_utilities["Direct_Home"] <- (need_weight * home_need_val) +
				                              u_home_base +
				                              (accessibility_weight * compute_accessibility_to_point(home_location));
			}
			
			// Option 2: Representative "Others" cell (social dinner / drinks / leisure meeting)
			if (!empty(others_utils)) {
				float max_uo <- max(others_utils.values);
				map<affordance_cell, float> others_probs <- [];
				loop c over: others_utils.keys { others_probs[c] <- exp(others_utils[c] - max_uo); }
				affordance_cell c_o <- rnd_choice(others_probs);
				if (c_o != nil) {
					d_utilities["Others"] <- others_utils[c_o];
					d_cell["Others"] <- c_o;
				}
			}
			
			// Option 3: Representative "Shop" cell (grocery shopping / market stop on commute home)
			if (!empty(shop_utils)) {
				float max_us <- max(shop_utils.values);
				map<affordance_cell, float> shop_probs <- [];
				loop c over: shop_utils.keys { shop_probs[c] <- exp(shop_utils[c] - max_us); }
				affordance_cell c_s <- rnd_choice(shop_probs);
				if (c_s != nil) {
					d_utilities["Shop"] <- shop_utils[c_s];
					d_cell["Shop"] <- c_s;
				}
			}
			
			if (!empty(d_utilities)) {
				float max_du <- max(d_utilities.values);
				map<string, float> d_probs <- [];
				loop k over: d_utilities.keys {
					d_probs[k] <- exp(d_utilities[k] - max_du);
				}
				string chosen_k <- rnd_choice(d_probs);
				if (chosen_k in ["Others", "Shop"]) {
					affordance_cell chosen_c <- d_cell[chosen_k];
					if (chosen_c != nil and chosen_c.reserve_slot(chosen_k)) {
						active_satisfied_need <- (chosen_k = "Shop") ? "shop" : ((internal_needs["hunger"] >= internal_needs["leisure"]) ? "hunger" : "leisure");
						current_affordance_cell <- chosen_c;
						affordance_origin_location <- (home_location != nil) ? home_location : location;
						affordance_origin_activity <- "Home";
						point dest_poi <- chosen_c.get_random_poi_location(chosen_k);
						do create_autonomous_trip(dest_poi, chosen_k, current_activity);
						evening_return_done <- true;
						evening_outing_done <- true;
						return;
					}
				}
			}
		}
		
		// 3. Default: Mandatory obligation is complete and no external detour chosen -> agent returns directly to Home
		point home_dest <- (home_location != nil) ? home_location : location;
		do create_autonomous_trip(home_dest, "Home", current_activity);
		evening_return_done <- true;
	}

	// ── Step 4.4 & 9.4: Multi-Criteria Discretionary Affordance Choice Action (MNL At Home / Discretionary Chaining) ──
	action evaluate_discretionary_affordance() {
		point base_target <- (affordance_origin_location != nil) ? affordance_origin_location : ((home_location != nil) ? home_location : location);
		string base_purpose <- (affordance_origin_activity != nil and affordance_origin_activity != "") ? affordance_origin_activity : "Home";
		
		// If at home before morning commute, allow quick pre-commute breakfast/exercise outings if at least 40 min remain before departure
		if (agenda_state = "At_Home" and morning_dep_time != nil and !morning_commute_done and current_date + 40 #minute >= morning_dep_time) {
			return;
		}
		
		// Once an evening activity or on-route detour has been completed, the agent stays home for the night
		if (agenda_state = "At_Home" and evening_outing_done) {
			return;
		}
		
		// Determine if any internal need ("hunger", "shop", "leisure") crosses tolerance threshold tau_d
		string active_need <- "";
		float max_need_gap <- 0.0;
		loop need_key over: internal_needs.keys {
			float threshold <- tau_need_thresholds[need_key];
			float gap <- internal_needs[need_key] - threshold;
			if (gap >= 0.0 and gap > max_need_gap) {
				max_need_gap <- gap;
				active_need <- need_key;
			}
		}
		
		// If no need is active:
		if (active_need = "") {
			if (agenda_state = "At_Discretionary") {
				agenda_state <- (base_purpose = "Home") ? "At_Home" : "At_Mandatory";
				if (location distance_to base_target > 50.0) {
					do create_autonomous_trip(base_target, base_purpose, current_activity);
				}
				affordance_origin_location <- nil;
				affordance_origin_activity <- "Home";
				return;
			}
			next_affordance_eval_time <- current_date + 15 #minute;
			return;
		}
		
		// Before morning mandatory commute, grocery shopping is deferred to the evening commute return or post-dinner
		if (agenda_state = "At_Home" and morning_dep_time != nil and !morning_commute_done and active_need = "shop") {
			next_affordance_eval_time <- morning_dep_time;
			return;
		}
		
		// Step A: Select representative "Others" cell and/or "Shop" cell via MNL with Log-Normal spatial search dispersion
		float base_r <- (active_need in need_perception_radius.keys) ? need_perception_radius[active_need] : 2183.0;
		float radius <- max(600.0, min(9500.0, base_r * exp(gauss(-0.10, 0.65))));
		list<affordance_cell> near_cells <- (affordance_cell at_distance radius) where (location distance_to each.location <= radius);
		if (empty(near_cells)) {
			near_cells <- [affordance_cell closest_to self];
		}
		list<string> eligible_pois <- (active_need in need_eligible_poi_types.keys) ? need_eligible_poi_types[active_need] : ["Others", "Shop"];
		
		map<affordance_cell, float> others_utils <- [];
		map<affordance_cell, float> shop_utils <- [];
		
		loop c over: near_cells {
			float cell_acc <- 0.0;
			bool acc_computed <- false;
			if ("Others" in eligible_pois and c.is_open("Others", current_date.hour) and c.get_remaining_capacity("Others") > 0 and !empty(c.poi_locations["Others"])) {
				cell_acc <- compute_multimodal_logsum_accessibility(c);
				acc_computed <- true;
				others_utils[c] <- (need_weight * internal_needs[active_need]) +
				                   (attractiveness_weight * c.poi_attractiveness["Others"]) -
				                   (crowding_weight * c.get_occupancy_ratio("Others")) +
				                   (accessibility_weight * cell_acc);
			}
			if ("Shop" in eligible_pois and c.is_open("Shop", current_date.hour) and c.get_remaining_capacity("Shop") > 0 and !empty(c.poi_locations["Shop"])) {
				if (!acc_computed) {
					cell_acc <- compute_multimodal_logsum_accessibility(c);
				}
				shop_utils[c] <- (need_weight * internal_needs[active_need]) +
				                 (attractiveness_weight * c.poi_attractiveness["Shop"]) -
				                 (crowding_weight * c.get_occupancy_ratio("Shop")) +
				                 (accessibility_weight * cell_acc) -
				                 (active_need = "hunger" ? hunger_shop_penalty : 0.0);
			}
		}
		
		// Step B: Fair macro MNL between [Stay_At_Home / Return_Base, Others, Shop]
		map<string, float> option_utilities <- [];
		map<string, affordance_cell> option_cell <- [];
		
		if (agenda_state = "At_Home") {
			if ("Home" in need_eligible_poi_types[active_need] and active_need in stay_at_home_utility.keys) {
				float u_home_val <- stay_at_home_utility[active_need];
				// Workday cognitive/physical fatigue: once a full mandatory work/study day is complete (or late evening >= 19h), domestic rest has an enhanced valuation, and >= 20h night rest/sleep dominates
				if (current_date.hour >= 20 and active_need in ["leisure", "hunger"]) {
					u_home_val <- 5.60;
				} else if (current_status = "Actif" and current_date.hour = 18 and evening_return_done and active_need in ["leisure", "hunger"]) {
					u_home_val <- 4.70;
				} else if (((evening_return_done and current_date.hour >= 17) or current_date.hour >= 19) and active_need in ["leisure", "hunger"]) {
					u_home_val <- (current_status = "Étudiant ou élève") ? 4.05 : 3.65;
				} else if (current_status = "Étudiant ou élève" and evening_return_done and current_date.hour >= 12 and current_date.hour < 17 and active_need in ["leisure", "hunger"]) {
					u_home_val <- 4.30;
				} else if (num_trip = 0 and current_date.hour >= 7 and current_date.hour < 20) {
					// Daylight mobility urge: someone who has not left home all day has lower domestic inertia to step outside
					u_home_val <- (active_need = "hunger") ? daylight_urge_hunger : daylight_urge_leisure;
				}
				option_utilities["Stay_At_Home"] <- (need_weight * internal_needs[active_need]) + u_home_val;
			}
		} else {
			// At Discretionary: returning to base (Home or anchor) is always an available affordance
			float u_home <- (active_need in stay_at_home_utility.keys) ? stay_at_home_utility[active_need] : stay_at_home_utility["leisure"];
			option_utilities["Return_Base"] <- (need_weight * internal_needs[active_need]) + u_home + (accessibility_weight * compute_accessibility_to_point(base_target));
		}
		
		if (!empty(others_utils)) {
			float max_uo <- max(others_utils.values);
			map<affordance_cell, float> others_probs <- [];
			loop c over: others_utils.keys { others_probs[c] <- exp(others_utils[c] - max_uo); }
			affordance_cell c_o <- rnd_choice(others_probs);
			if (c_o != nil) {
				option_utilities["Others"] <- others_utils[c_o];
				option_cell["Others"] <- c_o;
			}
		}
		
		if (!empty(shop_utils)) {
			float max_us <- max(shop_utils.values);
			map<affordance_cell, float> shop_probs <- [];
			loop c over: shop_utils.keys { shop_probs[c] <- exp(shop_utils[c] - max_us); }
			affordance_cell c_s <- rnd_choice(shop_probs);
			if (c_s != nil) {
				option_utilities["Shop"] <- shop_utils[c_s];
				option_cell["Shop"] <- c_s;
			}
		}
		
		if (empty(option_utilities)) {
			if (agenda_state = "At_Discretionary") {
				agenda_state <- (base_purpose = "Home") ? "At_Home" : "At_Mandatory";
				if (location distance_to base_target > 50.0) {
					do create_autonomous_trip(base_target, base_purpose, current_activity);
				}
				affordance_origin_location <- nil;
				affordance_origin_activity <- "Home";
				return;
			}
			next_affordance_eval_time <- current_date + 20 #minute;
			return;
		}
		
		float max_u <- max(option_utilities.values);
		map<string, float> option_probs <- [];
		loop k over: option_utilities.keys {
			option_probs[k] <- exp(option_utilities[k] - max_u);
		}
		string chosen_k <- rnd_choice(option_probs);
		if (chosen_k = nil or chosen_k = "") {
			if (agenda_state = "At_Discretionary") {
				agenda_state <- (base_purpose = "Home") ? "At_Home" : "At_Mandatory";
				if (location distance_to base_target > 50.0) {
					do create_autonomous_trip(base_target, base_purpose, current_activity);
				}
				affordance_origin_location <- nil;
				affordance_origin_activity <- "Home";
				return;
			}
			next_affordance_eval_time <- current_date + 20 #minute;
			return;
		}
		
		// Case 1: Stay_At_Home (domestic meal or domestic relaxation)
		if (chosen_k = "Stay_At_Home") {
			if ((current_status != "Étudiant ou élève" and (evening_return_done or current_date.hour >= 19)) or (current_status = "Étudiant ou élève" and (evening_return_done and current_date.hour >= 19)) or current_date.hour >= 20) {
				// Evening domestic relaxation/dinner fully satisfies leisure and hunger for the night
				internal_needs["hunger"] <- 0.0;
				internal_needs["leisure"] <- 0.0;
				evening_outing_done <- true;
				next_affordance_eval_time <- current_date + 180 #minute;
				return;
			}
			if (active_need = "hunger") {
				// Domestic kitchen meal fully satisfies hunger
				internal_needs["hunger"] <- 0.0;
				internal_needs["leisure"] <- max(0.0, internal_needs["leisure"] - 0.15);
			} else if (active_need = "leisure") {
				// Domestic relaxation partially relieves leisure need without wiping it to 0.0
				internal_needs["leisure"] <- max(0.0, internal_needs["leisure"] - 0.12);
				internal_needs["hunger"] <- max(0.0, internal_needs["hunger"] - 0.10);
			} else {
				internal_needs[active_need] <- 0.0;
			}
			next_affordance_eval_time <- current_date + 45 #minute;
			return;
		}
		
		// Case 2: Return_Base (agent was at discretionary location and chose to return to base)
		if (chosen_k = "Return_Base") {
			agenda_state <- (base_purpose = "Home") ? "At_Home" : "At_Mandatory";
			if (location distance_to base_target > 50.0) {
				do create_autonomous_trip(base_target, base_purpose, current_activity);
			}
			affordance_origin_location <- nil;
			affordance_origin_activity <- "Home";
			return;
		}
		
		// Case 3: Going to an affordance cell (Others or Shop)
		affordance_cell chosen_cell <- option_cell[chosen_k];
		if (chosen_cell = nil or !chosen_cell.reserve_slot(chosen_k)) {
			if (agenda_state = "At_Discretionary") {
				agenda_state <- (base_purpose = "Home") ? "At_Home" : "At_Mandatory";
				if (location distance_to base_target > 50.0) {
					do create_autonomous_trip(base_target, base_purpose, current_activity);
				}
				affordance_origin_location <- nil;
				affordance_origin_activity <- "Home";
				return;
			}
			next_affordance_eval_time <- current_date + 20 #minute;
			return;
		}
		
		active_satisfied_need <- active_need;
		current_affordance_cell <- chosen_cell;
		point dest_point <- chosen_cell.get_random_poi_location(chosen_k);
		
		if (agenda_state != "At_Discretionary") {
			affordance_origin_location <- location;
			affordance_origin_activity <- current_activity;
		}
		if (agenda_state = "At_Home" and ((evening_return_done and current_date.hour >= 17) or current_date.hour >= 18)) {
			evening_outing_done <- true;
		}
		agenda_state <- "At_Discretionary";
		do create_autonomous_trip(dest_point, chosen_k, current_activity);
	}
	
	// Reflex: evaluate affordances when idling at Home or at Discretionary
	reflex evaluate_and_trigger_affordance when: generate_activities and target = nil and current_trip = nil and activity_end_time = nil and (agenda_state in ["At_Home", "At_Discretionary"]) and (next_affordance_eval_time = nil or current_date >= next_affordance_eval_time) {
		do evaluate_discretionary_affordance;
	}

	// ── Step 4.5: Activity Completion & Need Reset Reflex (Discretionary & Morning Business Errands) ───────────────────
	reflex complete_affordance_activity when: generate_activities and current_affordance_cell != nil and activity_end_time != nil and current_date >= activity_end_time and target = nil and current_trip = nil and agenda_state != "At_Midday_Break" {
		string finished_act <- current_activity;
		
		if (is_business_errand) {
			is_business_errand <- false;
		} else {
			if (active_satisfied_need != "" and active_satisfied_need in internal_needs.keys) {
				internal_needs[active_satisfied_need] <- 0.0;
			} else if (finished_act = "Shop") {
				internal_needs["shop"] <- 0.0;
			} else if (finished_act = "Others") {
				internal_needs["leisure"] <- 0.0;
			}
			active_satisfied_need <- "";
		}
		
		current_affordance_cell.release_slot(finished_act);
		current_affordance_cell <- nil;
		activity_end_time <- nil;
		
		// If morning mandatory commute is imminent, route directly to Work/Education
		if (morning_dep_time != nil and !morning_commute_done and current_date + 25 #minute >= morning_dep_time) {
			point dest <- (work_location != nil) ? work_location : education_location;
			string dest_p <- (work_location != nil) ? "Work" : "Education";
			if (dest != nil) {
				morning_commute_done <- true;
				affordance_origin_location <- nil;
				affordance_origin_activity <- "Home";
				do create_autonomous_trip(dest, dest_p, finished_act);
				return;
			}
		}
		
		// Emergent chaining: evaluate next affordance or return home
		agenda_state <- "At_Discretionary";
		next_affordance_eval_time <- nil;
		do evaluate_discretionary_affordance;
	}

	reflex move when: target != nil { 
		previous_target <- location;
		//congestion
		if apply_congestion {
			if current_mode in mode_affected_by_congestion {
				float base_speed       <- speed_by_mode[current_mode];
				float local_density <- instant_heatmap[location];
				
				
//				to avoid self congetsion 
				float pcu <- (current_mode in pcu_by_mode.keys) ? pcu_by_mode[current_mode] : 0.0;
				
				float self_contribution <- pcu * congestion_scale_factor;
				float ambient_density <- max(0.0, local_density - self_contribution);
				
				if ambient_density > max_density {
					max_density <- ambient_density;
				}
				float current_max_slowdown <- (current_mode in heavy_slowdown_modes) ? max_slowdown_car : max_slowdown_factor;
				float congestion_factor <- 1.0 - min(current_max_slowdown, ambient_density / max_congestion_density);
				speed_m_s <- base_speed * congestion_factor;
			}
		}

		
		do goto(target: target, on: allowed_graph, speed: speed_m_s #m/#s, recompute_path:false);
		float segment_distance <- (previous_target distance_to location) / #meter;
		
		
		if current_mode in walk_modes {
			walk_distance_m <- walk_distance_m + segment_distance;
		} else if current_mode in transit_modes {
			transit_distance_m <- transit_distance_m + segment_distance;
		}		
		real_distance_m <- real_distance_m + segment_distance;
		
		float dist_km <- segment_distance / 1000.0;
		if used_weights{
        	dist_km <- dist_km * weight_survey;
        }
        total_km_by_mode[current_mode] <- total_km_by_mode[current_mode] + dist_km;
        
        float emission <- dist_km * co2_factors_g_km[current_mode];

        total_co2 <- total_co2 + emission;

		if location = target {
			
			float segment_duration <- (current_date - time_current_mode_start) / #minute;
			if current_trip.main_mode in pt_main_modes {
				do accumulate_mode_duration(segment_duration);
			}
			
			if used_weights{
	        	segment_duration <- segment_duration * weight_survey;
	        }
			total_min_by_mode[current_mode] <- total_min_by_mode[current_mode] + segment_duration;

			
			//arrived at final destination
			if length(trip_steps) = 0 {
				real_trip_duration_min <- (current_date - time_departure_current_trip) / #minute;
				
				if save_simulation {
					do save_trip_results();
				}

				current_activity <- current_trip.destination_purpose;
				target       <- nil;
				current_mode <- nil;
				current_trip <- nil;
				trip_steps <- [];
				time_current_mode_start <- nil;
				trip_structure <- nil;

				// Step 4.5 & 9: State machine transitions upon arrival at destination
				if (generate_activities) {
					if (is_on_break) {
						agenda_state <- "At_Midday_Break";
						float curr_h <- current_date.hour + current_date.minute / 60.0;
						float break_dur <- 0.0;
						if (has_evening_student_job and current_activity = "Home") {
							break_dur <- max(90.0, min(360.0, (gauss(16.5, 0.45) - curr_h) * 60.0));
						} else if (current_activity = "Home") {
							break_dur <- max(45.0, min(180.0, gauss(lunch_duration_mean_min, lunch_duration_std_min)));
						} else if (current_activity = "Shop") {
							break_dur <- max(10.0, min(35.0, gauss(20.0, 5.0)));
						} else {
							break_dur <- max(35.0, min(150.0, gauss(75.0, 28.0)));
						}
						activity_end_time <- current_date + (int(break_dur * 60) #sec);
					} else if (current_activity = "Home") {
						agenda_state <- "At_Home";
						activity_end_time <- nil;
					} else if (current_activity in ["Work", "Education"]) {
						agenda_state <- "At_Mandatory";
						if (is_business_errand) {
							float errand_dur <- max(30.0, min(90.0, gauss(50.0, 15.0)));
							activity_end_time <- current_date + (int(errand_dur * 60) #sec);
						} else if (break_taken_today and remaining_mandatory_min < 45.0) {
							remaining_mandatory_min <- 45.0;
						}
					} else if (current_activity = "Escort") {
						agenda_state <- "At_Mandatory";
						activity_end_time <- current_date + (int(escort_stay_duration_min * 60) #sec);
					} else if (current_activity in ["Shop", "Others"]) {
						agenda_state <- "At_Discretionary";
						float dur_min <- is_business_errand ? max(15.0, min(50.0, gauss(30.0, 8.0))) : sample_activity_duration(current_status, current_activity);
						activity_end_time <- current_date + (int(dur_min * 60) #sec);
					}
				}

			// Étape intermédiaire
			} else {
				
				do apply_next_step();				
			}
		   }
	 	}
	

	reflex chooseTarget when: (target = nil) and (current_trip != nil) and (current_trip.departure_time <= current_date) {
		current_activity         <- "moving";
		mode_survey              <- generate_activities ? "Autonomous" : current_trip.main_mode;
		current_mode             <- current_trip.main_mode;
		time_departure_current_trip <- current_date;
		target                   <- current_trip.destination_point;
		speed_m_s                <- speed_by_mode[current_mode];
		time_current_mode_start  <- current_date;
		walk_duration_min        <- 0.0;
		transit_duration_min     <- 0.0;
		waiting_duration_min     <- 0.0;
		previous_target          <- location;
		walk_distance_m          <- 0.0;
		transit_distance_m       <- 0.0;
		real_distance_m <- 0.0;
		trip_structure <- nil;
		trip_steps               <- [];
		color<- mode_color[current_trip.main_mode];  
		
		road start_road <- (road closest_to location);
		road end_road <- (road closest_to target);
		
		point start_point;
		point end_point;
		
		if start_road = nil or end_road = nil{
			start_point <- nil;
			end_point <- nil;
		} else{
			start_point <- closest_points_with(start_road, location)[0];
			end_point <- closest_points_with(end_road, target)[0];
		}
		
		if start_point = nil or end_point = nil {
			do abort_trip("Too far from area", nil);
		}
		else {
			path path_r_car <- path_between(road_graph_weighted_car, start_point, end_point);
			path path_r_scooter <- path_between(road_graph_weighted_scooter, start_point, end_point);
			path path_r_bike <- path_between(road_graph_weighted_bike, start_point, end_point);
			path path_r_walk <- path_between(road_graph, start_point, end_point);
			path path_b <- nil;
			path path_m <- nil;
			path path_pt <- nil;
			
			if multimodal {
				path_pt <- path_between(multimodal_graph_weighted, start_point, end_point);
			} else {
				path_b <- path_between(bus_graph_weighted, start_point, end_point);
				path_m <- path_between(metro_graph_weighted, start_point, end_point);
			}
			
			current_start_point <- start_point;
			current_end_point <- end_point;
			string chosen <- choose_mode(path_r_car, path_r_scooter, path_r_bike, path_r_walk, path_b, path_m, path_pt);
			mode_utility <- chosen;
			mode_distribution_utility[chosen] <- mode_distribution_utility[chosen] + 1;
			
			if generate_modes {
				current_mode <- chosen;
				current_trip.main_mode <- chosen;
			}
			if current_trip.main_mode in pt_main_modes {
				
				string w_mode <- "W_" + (current_trip.main_mode = "MTR" ? "MTR" : (current_trip.main_mode = "BUS" ? "BUS" : "PT"));
				string wait_mode <- "WAIT_" + (current_trip.main_mode = "MTR" ? "MTR" : (current_trip.main_mode = "BUS" ? "BUS" : "PT"));

				full_path <- multimodal ? path_pt : (current_trip.main_mode = "MTR" ? path_m : path_b);
				
				if full_path = nil or length(full_path.edges) = 0 {
					do abort_trip("Path nil for " + current_trip.main_mode, full_path);
				} else {
					trip_steps <- [];
					do build_step(start_point, w_mode, speed_by_mode["W"], true);
					trip_structure <- w_mode;
	
					do build_transit_steps(
						full_path.edges,
						current_trip.main_mode,
						w_mode,
						wait_mode,
						end_point
					);
					do build_step(target, w_mode, speed_by_mode["W"], true);
					trip_structure <- trip_structure + "-" + w_mode;
					do apply_next_step();
				}
			}
	
			// ── DIRECT MODE (car, motobike, walk) ─────────────────────
			else {
				full_path <- path_between(road_graph, start_point, end_point);
					
					
				if full_path = nil or length(full_path.edges) = 0 {
					do build_step(target,     current_mode, (current_mode in speed_by_mode.keys ? speed_by_mode[current_mode] : speed_m_s), true);
				} else {
					trip_steps <- [];
					do build_step(start_point,     current_mode, (current_mode in speed_by_mode.keys ? speed_by_mode[current_mode] : speed_m_s), true);
					do build_step(end_point,     current_mode, (current_mode in speed_by_mode.keys ? speed_by_mode[current_mode] : speed_m_s), false);
					do build_step(target, current_mode, (current_mode in speed_by_mode.keys ? speed_by_mode[current_mode] : speed_m_s), true);
	
					do apply_next_step();
					allowed_graph <- road_graph;
				}
				trip_structure <- current_mode;
			}
				
		}
		
	}

	// Step 4.6: Agent Liveness Guard (active throughout simulation when generate_activities is true)
	reflex no_more_trips when: !generate_activities and num_trip >= length(trips) and current_trip = nil {
		do die();
	}
	aspect mode {
		if current_trip != nil {
			draw circle(50) color: rgb((target = nil) ? rgb(mode_color[current_trip.main_mode].red, mode_color[current_trip.main_mode].green, mode_color[current_trip.main_mode].blue, 0.1) : mode_color[current_trip.main_mode]) border: #black;
		}
	}
	aspect focus_on_metro {
		if current_trip != nil and current_mode != nil{
			draw (current_trip.main_mode = "MTR") ? circle(150) : circle(1) color: rgb((current_mode = "MTR") ? #red : #yellow);
		}
	}
	aspect focus_on_bus {
		if current_trip != nil {
			draw (current_trip.main_mode = "BUS") ? circle(150) : circle(1) color: rgb((current_mode = "BUS") ? #red : (current_mode != nil ? mode_color[current_mode] : #grey));
		}
	}
	aspect trips {

	}
	
	aspect allTrips {  
		    loop t over:trips{
				if(drawAsArc){
		    	  draw curve(t.origin_point,t.destination_point,0.5,100, 0.5,90) end_arrow: 100 color:mode_color[t.main_mode];	
		    	}else{
		    	  draw line(t.origin_point, t.destination_point) color: mode_color[t.main_mode] width: 1 end_arrow: 100;
		    	}
			}	
	}
	
	aspect filterMode{
		if(whatToVisualize=nil){
			if(mode_to_display!="none"){
			  if current_trip != nil and current_mode != nil{ 	
				if(mode_to_display=current_trip.main_mode){		     
			     if(current_mode = current_trip.main_mode){
			       draw circle(100)  color: mode_color[current_mode];	
			     }else{
			     	draw square(200)  color: mode_color[current_mode];
			     }	 
			    }
			    draw circle(50) color: rgb((target = nil) ? rgb(mode_color[current_trip.main_mode], 0.1) : rgb(mode_color[current_trip.main_mode], 0.7) ) border: #black;
			  }
			}else{
				if current_trip != nil {
					draw circle(50) color: rgb((target = nil) ? rgb(mode_color[current_trip.main_mode], 0.1) : mode_color[current_trip.main_mode]) border: #black;
				}
			}			
		}else{
			if(whatToVisualize = "person id"){
				if(person_id=cycle){
			  		path the_path;
			  		int i<-0;
			  		draw circle(20) color:mode_color[current_trip.main_mode];
			  		draw "agent" + person_id  + "-" + current_activity + " trip: " + num_trip + " start: " + current_trip.departure_time.hour + ":" + current_trip.departure_time.minute +  ":" + current_trip.departure_time.second + " end: " + current_trip.arrival_time.hour + ":" + current_trip.arrival_time.minute + ":" + current_trip.arrival_time.second at:location color:mode_color[current_trip.main_mode] font:simulationFont;
				    draw "Activity: " + current_activity + " trip: " + num_trip  at:{location.x,location.y+20#px} color:mode_color[current_trip.main_mode] font:simulationFont;  
				   // draw "p" + person_id + " Trip: " + (num_trip + 1)  + " start: " + current_trip.departure_time.hour + ":" + current_trip.departure_time.minute +  ":" + current_trip.departure_time.second + " end: " + current_trip.arrival_time.hour + ":" + current_trip.arrival_time.minute + ":" + current_trip.arrival_time.second at:location color:mode_color[current_trip.main_mode] font:simulationFont;
					loop t over:trips{
						if(drawAsArc){
				    	 // draw curve(t.origin_point,t.destination_point,int(self)/length(person),100, 0.5,-90) end_arrow: 100 color:mode_color[t.main_mode];
				    	  draw curve(t.origin_point,t.destination_point,0.5,100, 0.5,90) end_arrow: 100 color:mode_color[t.main_mode];	
				    	}else{
				    	  draw line(t.origin_point, t.destination_point) color: #grey width: 3 end_arrow: 200;
				    	}
						//draw "trip " + i at:line(t.origin_point, t.destination_point).location color:mode_color[t.main_mode] size:1;
					    the_path <- allowed_graph path_between (t.origin_point, t.destination_point);
					    //draw "path " + i at:the_path.shape.location + {i,0}color:mode_color[t.main_mode] size:1;
					    draw line(the_path.shape.points) color: mode_color[t.main_mode] width: 5 end_arrow: 10;	
						i<-i+1;
					}	
				}
			}	
		}
	}
	aspect trajectory_z {
		draw circle(50) at:{location.x,location.y,person_id*2} color: rgb((target = nil) ? rgb(mode_color[current_trip.main_mode], 0.1) : mode_color[current_trip.main_mode]) border: #black;
		draw line(full_path.shape.points) at:{full_path.shape.location.x,full_path.shape.location.y,person_id*2} color: mode_color[current_trip.main_mode] width:2.5 ;
	}

	aspect anchors {
		if (home_location != nil) {
			draw square(80) at: home_location color: #blue border: #black;
		}
		if (work_location != nil) {
			draw triangle(90) at: work_location color: #red border: #black;
			if (home_location != nil) {
				draw line([home_location, work_location]) color: rgb(255, 0, 0, 80) width: 1;
			}
		}
		if (education_location != nil) {
			draw circle(50) at: education_location color: #green border: #black;
			if (home_location != nil) {
				draw line([home_location, education_location]) color: rgb(0, 255, 0, 80) width: 1;
			}
		}
	}

}