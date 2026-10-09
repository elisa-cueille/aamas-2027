/**
* Name: affordancecell
* Based on the internal empty template. 
* Tags: 
*/


model affordancecell

import "../Parameters.gaml"

species affordance_cell {

	int cell_id;
	int n_work;
	int n_education;
	int n_shop;
	int n_others;
	float s_work;
	float s_education;
	float s_shop;
	float s_others;
	string dominant;
	rgb color -> landuse_color[dominant];

	// Step 2.2: Map storing exact POI point locations per category inside this cell
	map<string, list<point>> poi_locations <- [
		"Shop"::[],
		"Others"::[],
		"Work"::[],
		"Education"::[]
	];

	// Capacities, Occupancy, Attractiveness, and Open Hours
	map<string, int> total_capacity <- ["Shop"::0, "Others"::0];
	map<string, int> occupant_count <- ["Shop"::0, "Others"::0];
	map<string, float> poi_attractiveness <- ["Shop"::0.0, "Others"::0.0, "Work"::0.0, "Education"::0.0];
	
	// Operational time windows [start_hour, end_hour] calibrated from Hanoi HTS survey
	map<string, list<int>> open_windows <- [
		"Shop"::[6, 20],
		"Others"::[5, 22],
		"Work"::[6, 21],
		"Education"::[6, 21]
	];

	action update_capacities(float scale_factor) {
		loop act over: base_capacity_per_poi.keys {
			float surf_m2 <- (act = "Shop") ? s_shop : s_others;
			float norm_surf <- surf_m2 / median_surface_per_poi[act];
			if (norm_surf > 0.0) {
				total_capacity[act] <- max(1, round(norm_surf * base_capacity_per_poi[act] * scale_factor));
			} else {
				total_capacity[act] <- 0;
			}
		}
	}

	action initialize_cell() {
		poi_attractiveness["Shop"] <- ln(1.0 + (s_shop / median_surface_per_poi["Shop"]));
		poi_attractiveness["Others"] <- ln(1.0 + (s_others / median_surface_per_poi["Others"]));
		poi_attractiveness["Work"] <- ln(1.0 + (s_work / median_surface_per_poi["Work"]));
		poi_attractiveness["Education"] <- ln(1.0 + (s_education / median_surface_per_poi["Education"]));
		
		do update_capacities(1.0);
	}

	init {
		do initialize_cell();
	}

	int get_remaining_capacity(string activity_type) {
		if (activity_type in total_capacity.keys) {
			return max(0, total_capacity[activity_type] - occupant_count[activity_type]);
		}
		return 999999;
	}

	bool is_open(string activity_type, int current_hour) {
		if (activity_type in open_windows.keys) {
			list<int> win <- open_windows[activity_type];
			if (length(win) >= 2) {
				return current_hour >= win[0] and current_hour <= win[1];
			}
		}
		return false;
	}

	bool reserve_slot(string activity_type) {
		if (activity_type in total_capacity.keys) {
			if (get_remaining_capacity(activity_type) > 0) {
				occupant_count[activity_type] <- occupant_count[activity_type] + 1;
				return true;
			}
			return false;
		}
		return true;
	}

	action release_slot(string activity_type) {
		if (activity_type in occupant_count.keys) {
			occupant_count[activity_type] <- max(0, occupant_count[activity_type] - 1);
		}
	}

	float get_occupancy_ratio(string activity_type) {
		if (activity_type in total_capacity.keys) {
			int tot <- total_capacity[activity_type];
			if (tot > 0) {
				return float(occupant_count[activity_type]) / float(tot);
			}
		}
		return 0.0;
	}

	point get_random_poi_location(string activity_type) {
		if (activity_type in poi_locations.keys) {
			list<point> pts <- poi_locations[activity_type];
			if (length(pts) > 0) {
				return one_of(pts);
			}
		}
		return any_location_in(shape);
	}

	aspect base {
		draw shape color: rgb(color, 0.4) border: rgb(100, 100, 100, 0.3) width: 1;
	}
}



