/**
* Name: NewModel
* Based on the internal empty template. 
* Tags: 
*/  
model HanoiMobilityModel
//species
import "species/road.gaml"
import "species/water.gaml"
import "species/park.gaml"
import "species/person.gaml" 
import "species/trip.gaml"
import "species/failed_destination.gaml" 
import "species/counting_point.gaml"
import "species/mobility_survey.gaml"
import "species/province.gaml"
import "species/station_bus.gaml"
import "species/station_metro.gaml"
import "species/road_bus.gaml"
import "species/road_metro.gaml"
import "species/affordance_cell.gaml"
//parameters 
import "Parameters.gaml"
global{
	//STATIC GIS
	file shape_file_province <- file("../includes/GIS/Vietnam_63_34/Hanoi_province_34.shp");
	file shape_file_water <- file("../includes/GIS/Natural/waterways.shp");
	file shape_file_park <- file("../includes/GIS/Natural/park.shp");
	// NETWORK GIS
	file shape_file_road <- file("../includes/GIS/Transport_Network/road_network.shp");
	file shape_file_metro <- file("../includes/GIS/Transport_Network/road_metro_"+metro_network+"_network.shp");
	file shape_file_metro_stations <- file("../includes/GIS/Transport_Network/stations_metro_"+metro_network+".shp");
	file shape_file_bus_stations <- file("../includes/GIS/Transport_Network/stations_bus_"+bus_network+".shp"); 
	file shape_file_bus <- file("../includes/GIS/Transport_Network/road_bus_"+bus_network+"_network.shp");
	file shape_file_multimodal;
    file shape_file_multimodal_stations;
    //COUNTING DATA
	file shape_file_counting_data <- file("../includes/GIS/Counting_Data/counting_point.shp");
	file shape_file_mobility_survey <- file("../includes/GIS/Vietnam_63_34/survey_zone.shp");
	//SURVEY DATA
	file csv_persons <- csv_file("../../../data_processing/survey/output/"+population_BD+"_persons.csv", ",", string, true);
	file csv_trips <- csv_file("../../../data_processing/survey/output/"+population_BD+"_trips.csv", ",", string, true);
	//LAND USE & SPATIAL AFFORDANCE GIS
	file shape_file_landuse <- file("../includes/GIS/LandUse/grid_landuse_" + (simulation_year >= 2050 ? "2050" : "2025") + "_300x300.shp");
	file csv_poi_locations <- csv_file("../includes/GIS/LandUse/cell_poi_locations_" + (simulation_year >= 2050 ? "2050" : "2025") + ".csv", ",", string, true);
	map<int, affordance_cell> cell_map;
	
	geometry shape <- envelope(shape_file_road);
	int size <- 100;
	field instant_heatmap <- field(size, size);
	field history_heatmap <- field(size, size);
	int total_weighted_people <- 0;
	
	float total_co2 <- 0.0;
	float total_congestion <- 0.0;
	float instant_congestion <- 0.0;
    map<string, float> total_km_by_mode <- [];
    map<string, float> total_min_by_mode <- [];
 
 	map<road, float> road_weights_scooter;
 	map<road, float> road_weights_car;
	map<road, float> road_weights_bike;
 	map<road_bus, float> bus_weights;
 	map<road_metro, float> metro_weights;
    map<public_transport, float> multimodal_weights;
	init{ 
		
		
		results_folder <- "../results/" + bus_network + "_" + metro_network + (generate_activities ? "_affordance/" : "/");
		if inversed_poi {
			shape_file_landuse <- file("../includes/GIS/LandUse/grid_landuse_scenario_inversion.shp");
			csv_poi_locations <- csv_file("../includes/GIS/LandUse/cell_poi_locations_scenario_inversion.csv", ",", string, true);
			results_folder <- results_folder + "inversion/";
		}
		do load_calibration_parameters("../includes/calibration_parameters.csv");

		write "results_folder " + results_folder;
		write "congestion "+apply_congestion;
		write "utility " + generate_modes;
		write "generate_activities " + generate_activities;
		write "save simulation "+save_simulation;
		write "BD " + population_BD;
		write "metro " + metro_network;
		write "bus " + bus_network;
		write "multimodale " + multimodal;
		write "start " + string(current_date.day);
		
		create water(type:string(read("fclass"))) from:shape_file_water; 
		create park(type:"park") from:shape_file_park; 
		create province from:shape_file_province;
		create counting_point from:shape_file_counting_data; 
		create mobility_survey from:shape_file_mobility_survey;
		
		// Affordance cells grid loading and fast O(1) cell_map indexing
		create affordance_cell from: shape_file_landuse with: [
			cell_id::int(read("cell_id")),
			n_work::int(read("n_Work")),
			n_education::int(read("n_Educatio")),
			n_shop::int(read("n_Shop")),
			n_others::int(read("n_Others")),
			s_work::float(read("s_Work")),
			s_education::float(read("s_Educatio")),
			s_shop::float(read("s_Shop")),
			s_others::float(read("s_Others")),
			dominant::string(read("dominant"))
		] {
			do initialize_cell();
		}
		cell_map <- affordance_cell as_map (each.cell_id :: each);
		write "Created " + length(affordance_cell) + " affordance cells.";
		
		if (generate_activities) {
			do loadCellPoiLocations();
		}
		
		
		if (multimodal) {
            shape_file_multimodal <- file("../includes/GIS/Transport_Network/output/road_bus_"+bus_network+"_metro_" + metro_network + "_networks.shp");
    		shape_file_multimodal_stations <- file("../includes/GIS/Transport_Network/output/stations_bus_"+bus_network+"_metro_" + metro_network + ".shp");
            create station(line_id:string(read ("line_id")), stop_id:int(read ("stop_id")), stop_seque:int(read("stop_seque")), mode:string(read("mode"))) from: shape_file_multimodal_stations;
            do createRoadMultimodal();
            
            multimodal_weights <- public_transport as_map (each :: each.weight);
            multimodal_graph_weighted <- directed(as_edge_graph(public_transport)) with_weights multimodal_weights;
            
            ask public_transport {
                weight <- shape.perimeter; 
            }
            multimodal_graph <- directed(as_edge_graph(public_transport));

        } else {
		//bus graph 
			create station_bus from: shape_file_bus_stations;
			do createRoadBus();
			bus_weights <- road_bus as_map (each :: each.weight);
			bus_graph_weighted <-  directed(as_edge_graph(road_bus)) with_weights bus_weights;
			ask road_bus  {
			    weight <- shape.perimeter;
			}
			bus_graph <- directed(as_edge_graph(road_bus));
	
	
			//metro graph
			create station_metro(line_id:string(read ("line_id")),stop_id:int(read ("stop_id")), stop_seque:int(read("stop_seque"))) from:shape_file_metro_stations;
		    do createRoadMetro(); 
			metro_weights <- road_metro as_map (each :: each.weight);
			metro_graph_weighted <-  directed(as_edge_graph(road_metro)) with_weights metro_weights;
			ask road_metro {
			    weight <- shape.perimeter;
			}
			
			metro_graph <- directed(as_edge_graph(road_metro));
			
		}


		//road graph
		create road from:shape_file_road;
		road_graph <- undirected(as_edge_graph(road));
		road_weights_car <- road as_map (each :: each.shape.perimeter);
		road_graph_weighted_car <- undirected(as_edge_graph(road)) with_weights road_weights_car;
		road_weights_scooter <- road as_map (each :: each.shape.perimeter);
		road_graph_weighted_scooter <- undirected(as_edge_graph(road)) with_weights road_weights_scooter;
		road_weights_bike <- road as_map (each :: each.shape.perimeter);
		road_graph_weighted_bike <- undirected(as_edge_graph(road)) with_weights road_weights_bike;
				
		//persons and their trips
		do createPerson(); 
		do createTrip();
		do updateTripDatesForMultiDaySimulation();
		do initPersonLocation();
		
		int total_p <- length(person);
		int with_h <- length(person where (each.home_location != nil));
		int with_w <- length(person where (each.work_location != nil));
		int with_e <- length(person where (each.education_location != nil));
		write "📍 [Spatial Anchors Initialization]";
		write "   - Total agents: " + total_p;
		write "   - Home (h_i):   " + with_h + " (" + (total_p > 0 ? (with_h / total_p * 100) with_precision 1 : 0) + "%)";
		write "   - Work (w_i):   " + with_w + " (" + (total_p > 0 ? (with_w / total_p * 100) with_precision 1 : 0) + "%)";
		write "   - Edu  (e_i):   " + with_e + " (" + (total_p > 0 ? (with_e / total_p * 100) with_precision 1 : 0) + "%)";
		
		// Scale congestion factor dynamically based on sample size (ref: 50.0 for 2,072 baseline agents)
		if (length(person) > 0) {
			congestion_scale_factor <- base_scale_factor * (2072 / length(person));
			write "Dynamic Congestion Scale Factor configured to: " + congestion_scale_factor + " for " + length(person) + " agents.";
		}
		
		// Scale affordance cell capacities dynamically based on sample size (ref: 2,072 baseline agents)
		float capacity_scale_factor <- (length(person) > 0) ? (length(person) / 2072.0) : 1.0;
		ask affordance_cell {
			do update_capacities(capacity_scale_factor);
		}
		write "📍 [Affordance Capacity Scaling] Configured (scale factor: " + (capacity_scale_factor with_precision 3) + ") for " + length(person) + " agents.";
		
//		update max values base on the number of persons 
				
		
		
		if used_weights{
			max_co2 <- 1.5 * total_weighted_people;
			max_km <- 13.0 * total_weighted_people;
			max_h <- 1.0 * total_weighted_people;
		} else {
			max_co2 <- max_co2*length(person);
			max_km <- max_km*length(person); 
			max_h <- max_h*length(person);
		}
		 max_instant_congestion <- max_instant_congestion*length(person);
		 max_total_congestion <- max_total_congestion*length(person);
		
		 if save_simulation {
		 	//initialization of single consolidated trip results CSV
			 save ["person_id", "weight", "trip_number", "dep_id", "mode", "mode_survey",
	              "departure_time", "arrival_time", "purpose", "real_min", "declared_min",
	              "real_distance_m", "crow_flies_distance_m",
	              "walk_duration_min", "transit_duration_min", "waiting_duration_min", "structure",
	              "origin_x", "origin_y", "destination_x", "destination_y"]
	        to: results_folder + "trip_durations.csv"
	        format: "csv"
	        rewrite: true
	        header: false;

	        if not(file_exists(results_folder + "modal_replications_history.csv")) {
	            save ["sim_id", "date", "count_sd", "count_cd", "count_pt", "count_w", "count_b", "total_trips", "pct_sd", "pct_cd", "pct_pt", "pct_w", "pct_b"]
	            to: results_folder + "modal_replications_history.csv" format: "csv" rewrite: false header: false;
	        }
		 }
		
		write "=== SIMULATION INITIALIZED ===";
	    write "Number of persons: " + length(person);
	    write "Number of weighted persons "+ total_weighted_people;
	    write "Use utility: " + generate_modes;
	    write "Multimodal: "+multimodal;
	    write "Starting date: " + starting_date;
	    write "Step: " + step +" seconds";
	    
	    write "======================================================================";
	    write "📋 [CALIBRATION PARAMETERS ACTIVE IN MEMORY]";
	    write "----------------------------------------------------------------------";
	    loop c over: lambda_need_rates_by_status.keys {
	    	write "  • " + c + " -> lambdas: " + lambda_need_rates_by_status[c];
	    }
	    write "  • Stay on site Work: " + stay_on_site_utility_work;
	    write "  • Stay on site Edu:  " + stay_on_site_utility_edu;
	    write "  • Stay at Home:      " + stay_at_home_utility;
	    write "  • Midday home lunch utility: " + midday_home_lunch_utility;
	    write "  • Hunger-shop penalty:       " + hunger_shop_penalty;
	    write "  • Daylight urge hunger:      " + daylight_urge_hunger;
	    write "  • Daylight urge leisure:     " + daylight_urge_leisure;
	    write "======================================================================";
	    
	    world_topology_graph <- topology(world);
    }       
      	reflex updateHeatmap when:apply_congestion{
		    // Lissage temporel : la congestion précédente s'estompe de 70% (conserve 30%)
		    instant_heatmap[] <- instant_heatmap[] * heatmap_retention;
		    ask (person where (each.target != nil)) {
//		    	PCU (Passenger Car Unit)
		        float pcu <- (current_mode in pcu_by_mode.keys) ? pcu_by_mode[current_mode] : 0.0;
		        
		        if pcu > 0 {
		            instant_heatmap[location] <- instant_heatmap[location] + pcu * congestion_scale_factor;
		            history_heatmap[location] <- history_heatmap[location] + pcu * 0.0002;
		        }
		    } 
		} 
		

		reflex computeCongestion when:apply_congestion{
		   instant_congestion <- 0.0; 
		   
		   loop square over:instant_heatmap{
		   		instant_congestion <- instant_congestion + square;
		   		total_congestion <- total_congestion + square;
		   }
		}
		
		reflex update_road_weights when: (apply_congestion and cycle mod 30 = 0) {
			loop rd over: road {
				float local_density <- instant_heatmap[rd.location];
				
				float congestion_car <- 1.0 - min(max_slowdown_car, local_density / max_congestion_density);
				road_weights_car[rd] <- rd.shape.perimeter / max(0.01, congestion_car);
				
				float congestion_scooter <- 1.0 - min(max_slowdown_factor, local_density / max_congestion_density);
				road_weights_scooter[rd] <- rd.shape.perimeter / max(0.01, congestion_scooter);
				
				float congestion_bike <- 1.0 - min(max_slowdown_factor, local_density / max_congestion_density);
				road_weights_bike[rd] <- rd.shape.perimeter / max(0.01, congestion_bike);
			}
			road_graph_weighted_car <- road_graph_weighted_car with_weights road_weights_car;
			road_graph_weighted_scooter <- road_graph_weighted_scooter with_weights road_weights_scooter;
			road_graph_weighted_bike <- road_graph_weighted_bike with_weights road_weights_bike;
		}
		
		reflex pollution_evolution when:pollution_diffusion{
			instant_heatmap <- instant_heatmap * 0.95;
			diffuse var: pollution on: instant_heatmap proportion: 1.0 radius:1;
		}
		reflex batch_heartbeat when: is_batch and (cycle mod 180 = 0) and (cycle > 0) and (cycle < 1440) {
			write "  [GAMA Simulation Progress] Hour " + current_date.hour + ":00 (cycle " + cycle + "/1440 - " + with_precision(cycle / 1440 * 100, 0) + "% of day)";
		}
    
		reflex end_one_day_simulation when: not(several_days_simulation) and (current_date.hour = 1) and ((current_date).day = 13) {
			do save_macro_indicators();
			if (!generate_activities) {
				int total_u_trips <- sum(mode_distribution_utility.values);
				write "=== SIMULATED MODAL DISTRIBUTION ===";
				loop m over: ["SD", "CD", "PT", "W", "B"] {
					write "  Mode " + m + " -> Trips: " + mode_distribution_utility[m] + " (" + (total_u_trips > 0 ? with_precision(mode_distribution_utility[m] / total_u_trips * 100, 2) : 0.0) + "%)";
				}
				if (save_simulation and total_u_trips > 0) {
					save [
						string(int(self)),
						string(current_date),
						mode_distribution_utility["SD"],
						mode_distribution_utility["CD"],
						mode_distribution_utility["PT"],
						mode_distribution_utility["W"],
						mode_distribution_utility["B"],
						total_u_trips,
						with_precision(mode_distribution_utility["SD"] / total_u_trips * 100, 2),
						with_precision(mode_distribution_utility["CD"] / total_u_trips * 100, 2),
						with_precision(mode_distribution_utility["PT"] / total_u_trips * 100, 2),
						with_precision(mode_distribution_utility["W"] / total_u_trips * 100, 2),
						with_precision(mode_distribution_utility["B"] / total_u_trips * 100, 2)
					] to: results_folder + "modal_replications_history.csv" format: "csv" rewrite: false header: false;
				}
			} else {
				int tot_gen <- sum(mode_distribution_utility.values);
				write "=== AUTONOMOUS ACTIVITY SIMULATION MODAL DISTRIBUTION ===";
				write "  Total Autonomous Trips Generated: " + tot_gen;
				loop m over: ["SD", "CD", "PT", "W", "B"] {
					float pct <- tot_gen > 0 ? (mode_distribution_utility[m] / tot_gen * 100) : 0.0;
					write "  Mode " + m + " -> Chosen Utility: " + mode_distribution_utility[m] + " (" + with_precision(pct, 1) + "%)";
				}
			}
			if (!is_batch) {
				IS_END <- true;
				do pause();
			}
//			write max_density;
		} 
		reflex end_several_days_simulation when: several_days_simulation and (current_date.hour = 1) and ((current_date).day = 30) and ((current_date).month = 3) and ((current_date).year = 2024) {
			do save_macro_indicators();
			if (!is_batch) {
				do pause();
			}
		}
		
		// Export species list for client
		list<string> species_list <- ["province","mobility_survey","park","water","road","station_bus","road_bus","road_metro","station_metro","public_transport", "person", "affordance_cell"]; 
		
	action loadCellPoiLocations() {
		if (csv_poi_locations != nil) {
			matrix data_poi <- matrix(csv_poi_locations);
			int nb_rows <- data_poi.rows;
			write "Loading " + nb_rows + " POI locations from CSV into affordance cells...";
			loop i from: 0 to: nb_rows - 1 {
				int c_id <- int(data_poi[0, i]);
				string cat <- string(data_poi[1, i]);
				affordance_cell c <- cell_map[c_id];
				if (c != nil) {
					if (cat in c.poi_locations.keys) {
						point pt <- c.location + {float(data_poi[2, i]), float(data_poi[3, i])};
						add pt to: c.poi_locations[cat];
					}
				}
			}
			write "POI locations loaded successfully into affordance cells.";
		}
	} 
		
    action createRoadBus(){
    	create road_bus(edge_type     :: string(read("edge_type")),
			    weight        :: float(read("weight")),
			    highway       :: string(read("highway")),
			    maxspeed      :: int(read("maxspeed")),
			    lanes         :: int(read("lanes")),
			    oneway        :: string(read("oneway")),
			    line_id       :: string(read("line_id")),
			    station_id    :: string(read("station_id")),
			    connector_dir :: string(read("connect_di")),
			    connector_speed :: float(read("cnnct_spd"))) from:shape_file_bus{
			    	color<- (edge_type = "connector" ? #red : (edge_type = "bus" ? mobility_color["BUS"] : #grey));
			    }
    }
    
    action createRoadMetro(){
    	create road_metro(edge_type     :: string(read("edge_type")),
			    weight        :: float(read("weight")),
			    highway       :: string(read("highway")),
			    maxspeed      :: float(read("maxspeed")),
			    lanes         :: float(read("lanes")), 
			    oneway        :: string(read("oneway")),
			    line_id       :: string(read("line_id")),
			    station_id    :: string(read("station_id")),
			    connector_dir :: string(read("connect_di")),
			    connector_speed :: float(read("cnnct_spd"))) from:shape_file_metro {
			    	color<-(edge_type = "connector" ? #red : (edge_type = "metro" ? mobility_color["MTR"]  : #grey));
			    }
    }
    action createRoadMultimodal(){
        create public_transport(
            edge_type       :: string(read("edge_type")),
            weight          :: float(read("weight")),
            highway         :: string(read("highway")),
            maxspeed        :: float(read("maxspeed")),
            lanes           :: float(read("lanes")), 
            oneway          :: string(read("oneway")),
            line_id         :: string(read("line_id")),
            station_id      :: string(read("station_id")),
            connector_dir   :: string(read("connect_di")),
            connector_speed :: float(read("cnnct_spd"))
        ) from: shape_file_multimodal;
    }

    action createPerson() {
		create person(
	            person_id:int(read("person_id")),
	            sex:string(read("sex")),
	            age:int(read("age")),
	            current_status:string(read("current_status")),
	            education_level:string(read("education_level")),
	            home_address:string(read("home_address")),
	            school_work_address:string(read("school_work_address")),
	            gas_car:int(read("gas_car")),
	            electric_car:int(read("electric_car")),
	            gas_scooter:int(read("gas_scooter")),
	            electric_scooter:int(read("electric_scooter")),
	            manual_bike:int(read("manual_bike")),
	            electric_bike:int(read("electric_bike")),
	            driving_license:read("driving_license"),
	            bus_subscription:read("bus_subscription"),
	            weight_survey:int(read("weight"))
	        ) from: csv_persons{
	        	total_weighted_people <- total_weighted_people + weight_survey;
	        	point h_pt <- point(read("home_location"));
	        	if (h_pt != nil and h_pt != {0.0, 0.0, 0.0} and h_pt != {0.0, 0.0}) {
	        		home_location <- to_GAMA_CRS(h_pt, "EPSG:4326").location;
	        	} else {
	        		home_location <- nil;
	        	}
	        	point w_pt <- point(read("work_location"));
	        	if (w_pt != nil and w_pt != {0.0, 0.0, 0.0} and w_pt != {0.0, 0.0}) {
	        		work_location <- to_GAMA_CRS(w_pt, "EPSG:4326").location;
	        	} else {
	        		work_location <- nil;
	        	}
	        	point e_pt <- point(read("education_location"));
	        	if (e_pt != nil and e_pt != {0.0, 0.0, 0.0} and e_pt != {0.0, 0.0}) {
	        		education_location <- to_GAMA_CRS(e_pt, "EPSG:4326").location;
	        	} else {
	        		education_location <- nil;
	        	}
	        }
	        
	
	}
	 action createTrip() {
		create trip(
	        trip_number:: int(read("trip_number")),
	        person_id:: int(read("person_id")),
	        day :: date(string(read("day")), "MM dd yyyy"),
	        dep_id:: int(read("dep_id")),
	        origin_purpose:: translate_purpose(string(read("origin_purpose"))),
	        destination_purpose:: translate_purpose(string(read("destination_purpose"))),
	        duration_minutes:: float(replace(string(read("duration_minutes")), ",", ".")),
	        main_mode:: survey_mode_to_acronym[string(read("main_mode"))], 
	        mode_1:: string(read("mode_1")),
	        mode_2:: string(read("mode_2")),
	        mode_3:: string(read("mode_3")),
	        origin_point :: to_GAMA_CRS({float(read("departure_longitude")), float(read("departure_latitude"))}, "EPSG:4326").location,
        	destination_point :: to_GAMA_CRS({float(read("arrival_longitude")), float(read("arrival_latitude"))}, "EPSG:4326").location,
        	departure_time :: date(string(read("departure_time")) replace (":", " "), "HH mm ss"),
        	arrival_time :: date(string(read("arrival_time")) replace(':', ' '), "HH mm ss")
	        ) from: csv_trips {
	        	person person_trip <- person first_with (each.person_id = person_id);
	        	add self to: person_trip.trips;
	        	//write "person " + person_id  + " trip " + trip_number;
	        }
	}
	action updateTripDatesForMultiDaySimulation() {
	    if several_days_simulation {
	        ask trip {
	            // save time
	            int dep_hour <- departure_time.hour;
	            int dep_minute <- departure_time.minute;
	            int dep_second <- departure_time.second;
	            
	            //change the date with the day variable
	            departure_time <- date([day.year, day.month, day.day, dep_hour, dep_minute, dep_second]);
	            
	     		//same thing for the arrivale_time
	            int arr_hour <- arrival_time.hour;
	            int arr_minute <- arrival_time.minute;
	            int arr_second <- arrival_time.second;
	            
	            arrival_time <- date([day.year, day.month, day.day, arr_hour, arr_minute, arr_second]);
	
	        }
	    }
	}
	action initPersonLocation() {
	    int persons_without_trips <- 0;	 
		ask person {
			if length(trips) > 0 {
				trips <- trips sort_by (each.dep_id);
				location <- (home_location != nil) ? home_location : trips[0].origin_point;
				current_activity <- trips[0].origin_purpose;
				if (home_location = nil) {
					home_location <- trips[0].origin_point;
				}
			} else {
				if (home_location != nil) {
					location <- home_location;
					current_activity <- "Home";
				} else {
					persons_without_trips <- persons_without_trips + 1;
					do die();
				}
			} }
//		write "⚠️ Persons without trips: " + persons_without_trips + " / " + length(person);
		
		// Initialize autonomous activity agendas when affordance model is active
		if (generate_activities) {
			ask person {
				do init_autonomous_schedule();
			}
			int nb_escort <- length(person where (each.is_school_escort));
			write "📍 [Emergent 3-Needs x 4-Affordances Agenda] Initialized for " + length(person) + " agents (" + nb_escort + " school escorts; breaks & secondary tours fully emergent).";
		}
	}
	
	action save_macro_indicators() {
		string file_path <- results_folder + "macro_indicators.csv";
        write "save macro indicators";
        save ["Mode", "Distance_KM", "Temps_MIN", "CO2_Grams gCO2"] to: file_path format: "csv" rewrite: true;
        
        loop m over: co2_factors_g_km.keys {
            float d <- total_km_by_mode[m];
            float t <- total_min_by_mode[m]; 
            float c <- d * co2_factors_g_km[m];
            save [m, d, t, c] to: file_path format: "csv" rewrite: false;
        }
        save ["TOTAL_SYSTEM", "", "", total_co2] to: file_path format: "csv" rewrite: false;
    }
}

//among: ["BD_Hanoi","synth_pop_2025_5k", "synth_pop_2025_10k"]
experiment Batch_Experiment type: batch repeat: 2 keep_seed: false until: (current_date.day = 13 and current_date.hour = 1) {
	parameter "Simulation Year" var: simulation_year <- 2024;
	parameter "Bus network" var: bus_network <- "current";
	parameter "Metro network" var: metro_network <- "2024";
	parameter "Population BD" var: population_BD <- "BD_Hanoi";
	init {
		write "start " + string(current_date.day);
	}
}

experiment run_baseline_24h type: batch repeat: 1 keep_seed: true until: (cycle >= 1441) {
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024];
	parameter "Generate activities" var: generate_activities <- false among: [false];
	parameter "Generate modes" var: generate_modes <- true among: [true];
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi"];
	parameter "Bus network" var: bus_network <- "current" among: ["current"];
	parameter "Metro network" var: metro_network <- "2024" among: ["2024"];
	parameter "Apply congestion" var: apply_congestion <- true among: [true];
	parameter "save" var: save_simulation <- true among: [true];
	parameter "batch" var: is_batch <- true among: [true];
}

experiment run_affordance_24h type: batch repeat: 1 keep_seed: false autorun: true until: (cycle >= 1441) {
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024];
	parameter "Generate activities" var: generate_activities <- true among: [true];
	parameter "Generate modes" var: generate_modes <- true among: [true];
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi"];
	parameter "Bus network" var: bus_network <- "current" among: ["current"];
	parameter "Metro network" var: metro_network <- "2024" among: ["2024"];
	parameter "Apply congestion" var: apply_congestion <- true among: [true];
	parameter "save" var: save_simulation <- true among: [true];
	parameter "batch" var: is_batch <- true among: [true];
}

experiment run_affordance_poi_inversed type: batch repeat: 1 keep_seed: false autorun: true until: (cycle >= 1441) {
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024];
	parameter "Generate activities" var: generate_activities <- true among: [true];
	parameter "Generate modes" var: generate_modes <- true among: [true];
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi"];
	parameter "Bus network" var: bus_network <- "current" among: ["current"];
	parameter "Metro network" var: metro_network <- "2024" among: ["2024"];
	parameter "Apply congestion" var: apply_congestion <- true among: [true];
	parameter "save" var: save_simulation <- true among: [true];
	parameter "batch" var: is_batch <- true among: [true];
	parameter "inversed_poi" var: inversed_poi <- true among: [true];
}

experiment affordance_poi_inversed type: gui parent: generic_exp autorun: false {
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024] category: "Simulation";
	parameter "Generate activities" var: generate_activities <- true among: [true] category: "Simulation";
	parameter "Generate modes" var: generate_modes <- true among: [true] category: "Simulation";
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi"] category: "Simulation";
	parameter "Bus network" var: bus_network <- "current" among: ["current"] category: "Simulation";
	parameter "Metro network" var: metro_network <- "2024" among: ["2024"] category: "Simulation";
	parameter "Apply congestion" var: apply_congestion <- true among: [true] category: "Simulation";
	parameter "save" var: save_simulation <- true category: "Simulation";
	parameter "inversed_poi" var: inversed_poi <- true among: [true] category: "Simulation";
	
	output {
		display map parent: base_map {}
	}
}

experiment affordance type: gui parent: generic_exp autorun: false {
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024] category: "Simulation";
	parameter "Generate activities" var: generate_activities <- true among: [true] category: "Simulation";
	parameter "Generate modes" var: generate_modes <- true among: [true] category: "Simulation";
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi"] category: "Simulation";
	parameter "Bus network" var: bus_network <- "current" among: ["current"] category: "Simulation";
	parameter "Metro network" var: metro_network <- "2024" among: ["2024"] category: "Simulation";
	parameter "Apply congestion" var: apply_congestion <- true among: [true] category: "Simulation";
	parameter "save" var: save_simulation <- true category: "Simulation";
	parameter "inversed_poi" var: inversed_poi <- false among: [false] category: "Simulation";
	
	output {
		display map parent: base_map {}
	}
}



experiment generic_exp type:gui {
	parameter "Multimodal" var: multimodal <- multimodal among: [true, false] category:"Simulation";
	parameter "Generate activities" var: generate_activities <- true among: [true, false] category:"Simulation";
	parameter "Generate modes" var: generate_modes <- true among: [true, false] category:"Simulation";
	parameter "Mode to show" var:mode_to_display <- "none" among:["none","BUS","MTR","PT"] category:"UX/UI";
	parameter "Show HeatMap Congestion" var:display_heatmap <- false category:"UX/UI";
	parameter "Show Land Use" var: display_landuse <- true category:"UX/UI";

	output {
		display base_map type: 3d background: background_color axes:true autosave:false toolbar:true	{
			overlay position: {5, 5} size: {10 #px, 10 #px} background: background_color transparency: 0.0 border: background_color rounded: true visible:display_overlay{
				float spacebetweenItemY <- 15 #px;
				float spacebetweentextY <- 30 #px;
				point position_legend <- {10 #px, 500 #px};
			    string hour_str <- (current_date.hour < 10 ? "0" + current_date.hour : "" + current_date.hour);
			    string min_str <- (current_date.minute < 10 ? "0" + current_date.minute : "" + current_date.minute);
			    string date_str<-hour_str + ":" + min_str ;
			    if(display_legend){
					draw "Simulation year: " + string(simulation_year) at: position_legend color: text_color font: titleFont;
					position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
					draw "Time: " + string(date_str) + " - Utility mode: " + generate_modes  + " - Pop: " + population_BD at: position_legend color: text_color font: textFont;
					position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
					
					if(display_ux_legend){
						draw string("People (p): " + string(display_person ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(7.5#px) color: #grey border:#black at: position_legend;
						if (display_mode){
							int i <- 0;
							position_legend <- {position_legend.x+50#px, position_legend.y + spacebetweentextY};
							loop mode over: mode_color_legend.keys {
								draw circle(5 #px) at: position_legend color: mode_color_legend[mode] border: #white;
	                            draw mode  at: position_legend + {20 #px, 5 #px} color: mode_color_legend[mode]  font: textFont;
	                        	position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
								i <- i + 1;
							}
						}
						position_legend <- {position_legend.x-50#px, position_legend.y + spacebetweentextY};
						draw string("Transport Network (n): " + string(display_network ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw square(15#px) color: #grey border:#black at: position_legend;
						position_legend <- {position_legend.x+50#px, position_legend.y + spacebetweentextY};
						draw string("Road (r): " + string(display_road ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: mobility_color["road"] font: textFont;
						draw square(10 #px) color: mobility_color["road"] at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
						draw string("Bus-" +bus_network + " (b): " + string(display_bus ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: mobility_color["BUS"] font: textFont;
						draw square(10 #px) color: mobility_color["BUS"] at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
						draw string("Metro-" + metro_network +" (m): " + string(display_metro ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: mobility_color["MTR"] font: textFont;
						draw square(10 #px) color: mobility_color["MTR"] at: position_legend;
						position_legend <- {position_legend.x-50#px, position_legend.y + spacebetweentextY};

						draw string("Land Use (l): " + string(display_landuse ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw square(15#px) color: #grey border:#black at: position_legend;
						if (display_landuse) {
							position_legend <- {position_legend.x+50#px, position_legend.y + spacebetweentextY};
							loop lu over: landuse_color.keys {
								draw square(8 #px) at: position_legend color: landuse_color[lu] border: #white;
								draw lu at: position_legend + {20 #px, 5 #px} color: landuse_color[lu] font: textFont;
								position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
							}
							position_legend <- {position_legend.x-50#px, position_legend.y + spacebetweentextY};
						} else {
							position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
						}

						draw string("Anchors (a): " + string(display_anchors ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw square(15#px) color: #grey border:#black at: position_legend;
						if (display_anchors) {
							position_legend <- {position_legend.x+50#px, position_legend.y + spacebetweentextY};
							draw square(8 #px) at: position_legend color: #blue border: #white;
							draw "Home (h)" at: position_legend + {20 #px, 5 #px} color: #blue font: textFont;
							position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
							draw triangle(9 #px) at: position_legend color: #red border: #white;
							draw "Work (w)" at: position_legend + {20 #px, 5 #px} color: #red font: textFont;
							position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
							draw circle(5 #px) at: position_legend color: #green border: #white;
							draw "Edu  (e)" at: position_legend + {20 #px, 5 #px} color: #green font: textFont;
							position_legend <- {position_legend.x-50#px, position_legend.y + spacebetweentextY};
						} else {
							position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
						}
					}

					if(display_legend_debug){
						position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
						draw string("Failed destinations (f): " + string(display_failed_destinations ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(5 #px) color: #red at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
						draw string("Counting point  (c): " + string(display_counting_points ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(5 #px) color: #red at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweenItemY};
						draw string("Water  (w): " + string(display_water ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(5 #px) color: #darkblue at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
					    draw string("Water  (w): " + string(display_water ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(5 #px) color: mobility_color["water"] at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
						draw string("Survey Area  (s): " + string(display_survey ? "true" : "false")) at: position_legend + {20 #px, 5 #px} color: text_color font: textFont;
						draw circle(5 #px) color: mobility_color["area"] at: position_legend;
						position_legend <- {position_legend.x, position_legend.y + spacebetweentextY};
					}
				}
			}
            species province aspect: base refresh:false;
            species mobility_survey aspect:base visible:display_survey refresh:false;
            species affordance_cell aspect: base visible: display_landuse refresh:false;
            species park aspect: base visible: display_water;
            species water aspect: base visible: display_water refresh:false;
            species road aspect: base visible: (display_road and display_network) refresh:false;
			species station_bus aspect: base visible: (display_bus and display_network);
			species road_bus aspect: public  visible: (display_bus  and display_network);
			species road_metro aspect: public  visible: (display_metro and display_network);
			species station_metro aspect: base visible: (display_metro and display_network);
			species public_transport aspect: multimode visible: multimodal;
			species person aspect: filterMode visible: display_person trace:0 fading:true;	
			species person aspect: anchors visible: display_anchors;
			species failed_destination aspect: base visible: display_failed_destinations;
			species counting_point aspect: base visible: display_counting_points;
			mesh instant_heatmap scale: 0 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal visible: display_heatmap;
			event "f" {display_failed_destinations <- !display_failed_destinations;}
			event "p" {display_person <- !display_person;}
			event "a" {display_anchors <- !display_anchors;}
			event "n" {display_network <- !display_network;}
			event "r" {display_road <- !display_road;}
			event "m" {display_metro <- !display_metro;}
			event "b" {display_bus <- !display_bus;}
			event "c" {display_counting_points <- !display_counting_points;}
			event "w" {display_water <- !display_water;} 
			event "s" {display_survey <- !display_survey;}
			event "l" {display_landuse <- !display_landuse;}
			event "h" {display_heatmap <- !display_heatmap;}//apply_congestion<-!apply_congestion;}
		} 
	}
}


experiment exportResults type: gui autorun: true{
	parameter "Simulation Year" var: simulation_year <- 2024 among: [2024, 2026, 2030, 2050] category:"Simulation";
	parameter "Bus network" var: bus_network <- "current" among: ["current", "ttk"] category:"Simulation";
	parameter "Metro network" var: metro_network <- "2024" among: ["2024", "2026","2030","2050"] category:"Simulation";
	parameter "Population BD" var: population_BD <- "BD_Hanoi" among: ["BD_Hanoi","synth_pop_2025_10k", "synth_pop_2050_10k"] category:"Simulation";
	parameter "Apply congestion" var: apply_congestion <- true category: "Simulation";
	parameter "batch" var: is_batch <- false category: "Simulation";
	parameter "multimodal" var: multimodal <- true category: "Simulation";
	parameter "save" var: save_simulation <- true category: "Simulation";
	parameter "Generate activities" var: generate_activities <- false among: [false, true] category: "Simulation";
	parameter "Generate modes" var: generate_modes <- true among: [true, false] category: "Simulation";
}

 
experiment Simulation_2024_Modal_Distribution type: gui parent:generic_exp{
	action _init_(){ 
		create simulation(simulation_year: 2024, bus_network: "current", metro_network:"2024", population_BD:"BD_Hanoi",generate_modes:true,color:#orange,display_ux_legend:false);
	}
	output{
	  display map parent:base_map{}	
	  display "Modal Distribution" {
        chart "Trips per mode" type: series x_label: "Time" y_label: "Nb Trips" {
            loop mode over: ["SD", "CD", "PT", "W", "B"] {
                data mode value: mode_distribution_utility[mode] color: mode_color[mode];
            }
        }
	  }
	}
}


experiment Simulation_2024_vs_2026_vs_2030_vs_2050 type: gui parent:generic_exp{
	action _init_(){ 
		create simulation(simulation_year: 2024, bus_network: "current", metro_network:"2024", population_BD:"BD_Hanoi",color:#red, display_ux_legend:false);
		create simulation(simulation_year: 2026, bus_network: "current", metro_network:"2026",population_BD:"BD_Hanoi",color:#orange, display_ux_legend:false);
		create simulation(simulation_year: 2030, bus_network: "ttk", metro_network:"2030", population_BD:"BD_Hanoi",color:#yellow, display_ux_legend:false);
		create simulation(simulation_year: 2050, bus_network: "ttk", metro_network:"2050", population_BD:"BD_Hanoi",color:#green, display_ux_legend:false);
	}
output{
		  display map parent:base_map{}
	} 
	permanent{
	    display "Key Performance Indicator" type: 2d
		{ 
			chart "Key Performance Indicator" type: radar x_serie_labels: ["K CO2","KM Bus", "KM Metro", "KM walk","KM Car", "KM Moto", "Congestion", "Duration Bus", "Duration Metro", "Duration walk", "Duration Car", "Duration Moto"] 
	        series_label_position: xaxis { 
	            loop s over: simulations {	
	                data string(s.simulation_year) value: [
	                    min(1.0, (s.total_co2 / 1000) / max_co2),
	                    min(1.0, s.total_km_by_mode["BUS"] / max_km), 
	                    min(1.0, s.total_km_by_mode["MTR"] / max_km),
	                    min(1.0, (s.total_km_by_mode["W"] + s.total_km_by_mode["W_MTR"]+ s.total_km_by_mode["W_BUS"]) / max_km),
	                    min(1.0, (s.total_km_by_mode["CD"] + s.total_km_by_mode["CP"] + s.total_km_by_mode["CTX"]) / max_km),
						min(1.0, (s.total_km_by_mode["SP"] + s.total_km_by_mode["SD"]+ s.total_km_by_mode["STX"]) / max_km),
						min(1.0, s.total_congestion / max_total_congestion),
	                    min(1.0, (s.total_min_by_mode["BUS"] / 60) / max_h),
	                    min(1.0, (s.total_min_by_mode["MTR"] / 60) / max_h),
	                    min(1.0, ((s.total_min_by_mode["W"] + s.total_min_by_mode["W_MTR"]+ s.total_min_by_mode["W_BUS"]) / 60) / max_h),
	                    min(1.0, ((s.total_min_by_mode["CD"] + s.total_min_by_mode["CP"] + s.total_min_by_mode["CTX"]) / 60) / max_h),
	                    min(1.0, ((s.total_min_by_mode["SP"] + s.total_min_by_mode["SD"]+ s.total_min_by_mode["STX"]) / 60) / max_h)
	                    
	                ] color: s.color marker: true marker_size: 1.0;
	            }
			}
		}
	}
}



