/**
* Name: Parameters
* Based on the internal empty template. 
* Tags: 
*/

model Parameters

global {
	//simulation configuration

	float step <- 60 #sec;
	date starting_date <- date([2023,12,12,1,0,0]);
	bool several_days_simulation <- false;
	bool just_metro_line_from_survey <- false;
	bool apply_congestion <- true;
	bool display_heatmap <- false;
	bool pollution_diffusion <- false;
	bool addNoiseinDepartureTime <- true; // TO AVOID WEIRD RENDERING OF PEOPLE ALL LIVING AT THE SAME TIME (COULD BE DONE IN A SMARTER WAY)
	int simulation_year <- 2024;
	string bus_network <- "current";
	string metro_network <- "2024";
	string results_folder <- "../results/" + bus_network + "_" + metro_network + "/";
//	string population_BD<-"BD_Hanoi";
	string population_BD<-"BD_Hanoi";
	bool debug <- false;
	bool save_simulation <- true;
	bool generate_modes <- true;
	bool generate_activities <- true;
	bool inversed_poi <- false;
	bool used_weights <- false;
	bool multimodal <- true;
	bool is_batch <- false;
	
	bool use_affordance_model -> generate_activities;
	
	
	// ── Spatial Affordance & 3-Needs Model Parameters (hunger, shop, leisure) ──
	// Need accumulation rate per hour by socio-professional status
	// Calibrated so hunger (reset to 0 at morning departure ~07:35, arrival ~08:05) crosses tau=0.50 after ~3.5h (~11:35 AM), and Shop rates reflect empirical replenishment cycles (13-15% daily shopping for Actif/Student, 33-51% for Retired/Homemakers)
	map<string, map<string, float>> lambda_need_rates_by_status <- [
		"Actif"::[
			"hunger":: 0.1286700302000042,
			"shop":: 0.0063244375661679,
			"leisure":: 0.0315385113353773
		],
		"Étudiant ou élève"::[
			"hunger":: 0.1415330923136716,
			"shop":: 0.006016094668074,
			"leisure":: 0.0247867620882349
		],
		"Retraité"::[
			"hunger":: 0.0497720176203568,
			"shop":: 0.0115990014440953,
			"leisure":: 0.047313378733578
		],
		"Personne au foyer"::[
			"hunger":: 0.0785812282774385,
			"shop":: 0.0104202108473673,
			"leisure":: 0.0517759965158027
		],
		"Sans emploi"::[
			"hunger":: 0.0583518644049849,
			"shop":: 0.0032386665090965,
			"leisure":: 0.0252943640591149
		]
	];
	
	// Need activation thresholds (tau_d)
	map<string, float> tau_need_thresholds <- [
		"hunger"::0.50,
		"shop"::0.45,
		"leisure"::0.52
	];
	
	// Spatial perception distance by activity type and by internal need (from empirical distance analysis, in meters)
	map<string, float> affordance_perception_radius <- [
		"Shop"::2183.0,
		"Others"::3800.0
	];

	map<string, float> need_perception_radius <- [
		"hunger"::1500.0,
		"shop"::2183.0,
		"leisure"::3800.0
	];

	// Parameter-free mapping of which POI types satisfy each internal need (Home does NOT satisfy shop)
	map<string, list<string>> need_eligible_poi_types <- [
		"hunger"::["Home", "Others", "Shop"],
		"shop"::["Shop"],
		"leisure"::["Home", "Others"]
	];


	// On-site Stay / Deferral baseline utilities at Work vs Education in 4-way MNL [Stay, Home, c_Others*, c_Shop*]
	// At Work: calibrated to reproduce empirical 635 on-site presence at 12:30 (survey) with ~85 Others and ~55 Home
	map<string, float> stay_on_site_utility_work <- [
		"hunger":: 4.888072639881374,
		"shop":: 4.664043096231342,
		"leisure":: 4.425980378066618
	];

	// At Education: calibrated for fair balance between on-site lunch, external street-food/cafe, and home lunch
	map<string, float> stay_on_site_utility_edu <- [
		"hunger":: 3.878684756886931,
		"shop":: 3.21780645496338,
		"leisure":: 4.300255745108361
	];

	// Midday lunch break at Home baseline utility (from workplace/school within space-time prism)
	float midday_home_lunch_utility <- 2.878612312514372;

	// Baseline utility of satisfying/resolving the need at Home (domestic dinner/kitchen meal for hunger, domestic leisure/rest for leisure, deferral/inventory for shopping).
	map<string, float> stay_at_home_utility <- [
		"hunger":: 4.327617384328897,
		"shop":: 1.809332436088204,
		"leisure":: 3.259526375003412
	];

	// Detour factors measured on Hanoi network
	map<string, float> detour_factors <- [
		"W"::1.45,
		"B"::1.29,
		"SD"::1.34,
		"CD"::1.40,
		"PT"::1.45,
		"BUS"::1.45,
		"MTR"::1.45
	];

	// Activity duration by status and purpose
	map<string, map<string, list<int>>> activity_duration_by_status <- [
		"Actif"::[
			"Shop"::[20, 80],
			"Others"::[20, 90]
		],
		"Étudiant ou élève"::[
			"Shop"::[15, 60],
			"Others"::[35, 120]
		],
		"Retraité"::[
			"Shop"::[20, 60],
			"Others"::[30, 90]
		],
		"Personne au foyer"::[
			"Shop"::[25, 60],
			"Others"::[30, 100]
		],
		"Sans emploi"::[
			"Shop"::[15, 45],
			"Others"::[30, 90]
		]
	];
	
	// Log-Normal distribution parameters: [mu, sigma]
	// Sampling: duration_min = exp(gauss(mu, sigma))
	map<string, map<string, list<float>>> activity_lognormal_params <- [
		"Shop":: [
			"Actif":: [3.634, 0.973],
			"Étudiant ou élève":: [3.454, 1.222],
			"Retraité":: [3.610, 0.730],
			"Personne au foyer":: [3.641, 0.774],
			"Sans emploi":: [3.570, 1.000]
		],
		"Others":: [
			"Actif":: [3.843, 1.200],
			"Étudiant ou élève":: [4.281, 1.027],
			"Retraité":: [4.047, 1.231],
			"Personne au foyer":: [3.966, 1.250],
			"Sans emploi":: [4.368, 0.803]
		]
	];
	
	// Activity duration sampling model: "distribution" (Log-Normal) or "intervalle"
	string activity_duration_model <- "distribution" among: ["distribution", "intervalle"];
	
	// ── Step 8: Mandatory Anchor Schedule & Break Affordance Parameters ───────────

	// Mandatory morning departure distributions (Gaussian [mean_hour, std_hour])
	// Work morning shift (93.5% of Actif): mean 07:25 (7.42h), std 41 min (0.68h), bounded [5.5, 11.0]h
	float work_dep_mean_hour <- 7.42;
	float work_dep_std_hour  <- 0.68;

	// Work afternoon/evening shift (6.5% of Actif + working students with both Education & Work anchors):
	// Departure mean 14:00 (14.00h), std 1.1h; Work duration median 291 min (4.85h -> mu=5.673, sigma=0.350)
	float prob_worker_afternoon_shift    <- 0.065;
	float work_afternoon_dep_mean_hour   <- 14.00;
	float work_afternoon_dep_std_hour    <- 1.10;
	float work_late_duration_lognormal_mu    <- 5.673;
	float work_late_duration_lognormal_sigma <- 0.350;

	// Education empirical regimes from survey (N=721 true students, excluding adult Escorts & subtracting breaks):
	// 1. Morning-Only (47.0% of all students = 56.6% of morning departures): dep mean 7.13h (std 0.89h), net median 270 min (4.50h) -> mu=5.445, sigma=0.332
	// 2. Full-Day (36.1% of all students = 43.4% of morning departures): dep mean 7.37h (std 1.06h), net study median 474 min (7.90h, breaks removed!) -> mu=6.098, sigma=0.296
	// 3. Afternoon-Only (16.9% of all students): dep mean 13.13h (std 0.85h), net median 200.5 min (3.34h) -> mu=5.298, sigma=0.412
	float edu_dep_mean_hour                  <- 7.231;
	float edu_dep_std_hour                   <- 0.962;
	float prob_student_afternoon_shift       <- 0.104; // 66 / 636 students departing after 10:00 in survey (10.4%)
	float prob_student_morning_halfday       <- 0.566; // 339 / 599 morning-departing students (47.0% of all students)
	float edu_afternoon_dep_mean_hour        <- 13.13;
	float edu_afternoon_dep_std_hour         <- 0.85;

	float edu_fullday_lognormal_mu           <- 6.098; // Full-Day net study time (breaks removed): median 474 min (7.90h)
	float edu_fullday_lognormal_sigma        <- 0.296;
	float edu_morning_half_lognormal_mu      <- 5.445; // Morning-Only net study time: median 270 min (4.50h)
	float edu_morning_half_lognormal_sigma   <- 0.332;
	float edu_afternoon_lognormal_mu         <- 5.298; // Afternoon-Only net study time: median 200.5 min (3.34h)
	float edu_afternoon_lognormal_sigma      <- 0.412;

	// School escort drop-off departure (for adults with child school e_i)
	float escort_dep_mean_hour     <- 7.25; // 07:15 AM
	float escort_dep_std_hour      <- 0.25; // 15 min std
	float escort_stay_duration_min <- 5.0;  // 5 min drop-off at school

	// Net daily work duration for morning-shift workers (calibrated on workers taking midday breaks: median=490.5 min = 8.18h -> mu=6.213, sigma=0.212)
	// Matching survey mean 17:35 and median 17:30 work exit (490 min net work + 55 min midday break = 545 min presence)
	float work_duration_lognormal_mu    <- 6.213;
	float work_duration_lognormal_sigma <- 0.212;

	// Global fallback Education Log-Normal parameters (across all regimes)
	float edu_duration_lognormal_mu    <- 5.658;
	float edu_duration_lognormal_sigma <- 0.474;

	// Break duration distributions (on-site canteen/lunchbox vs external Home/Others/Shop)
	float onsite_lunch_duration_mean_min <- 55.0;  // 55 min on-site lunch break at Work/Education so afternoon shift finishes on time (~16:45-17:15)
	float onsite_lunch_duration_std_min  <- 15.0;  // 15 min std
	float lunch_duration_mean_min        <- 72.0;  // 1.20h (72 min) net meal stay + siesta (nghi trua) at Home (plus ~30m travel -> return to work at ~13h05-13h25)
	float lunch_duration_std_min         <- 25.0;  // 25 min std, bounded [45, 180] min

	// Home affordance choice parameters during hunger breaks
	float midday_perception_radius    <- 1500.0; // Perception radius around workplace/school for breaks (1,500 m)
	float midday_home_max_dist        <- 5000.0; // 90th percentile distance to Home for lunch breaks (5,000 m)

	// Evening school escort pick-up parameters
	float escort_pickup_mean_hour     <- 16.75; // 16:45 PM for afternoon school pick-up
	float escort_pickup_std_hour      <- 0.35;  // 21 min std

	// Circadian metabolic sleep attenuation factor (replaces artificial night curfew)
	// Basal metabolic slowdown during nocturnal rest hours (23:00 to 06:00)
	float night_metabolic_factor      <- 0.15;

	// Daylight mobility urge parameters (lower domestic inertia for agents who have not left home all day)
	float daylight_urge_hunger        <- 2.177568067643653;
	float daylight_urge_leisure       <- 2.0684081990701566;
	
	float need_weight <- 2.0; // motivation of the agent to do the activity corresponding to the need
	float attractiveness_weight  <- 0.55; // Spatial POI attractiveness sensitivity coefficient (Step A)
	float crowding_weight    <- 1.0; // Local crowding penalty weight
	float accessibility_weight <- 0.28; // Multimodal Logsum accessibility sensitivity coefficient (Step A)
	float hunger_shop_penalty <- 2.0911255078610416;

	// Base capacity per POI for secondary activities (reference: 2,072 agents)
	map<string, float> base_capacity_per_poi <- [
		"Shop"::0.2,       // 1 spot for 5 median-sized shops
		"Others"::0.2      // 1 spot for 5 median-sized services or leisure places
	];

	// Median building surface (m²) per POI category in Hanoi (used to normalize cell surfaces)
	map<string, float> median_surface_per_poi <- [
		"Shop"::100.79,
		"Others"::110.26,
		"Work"::121.01,
		"Education"::142.10
	];

	map<string, rgb> landuse_color <- [
		"Shop"::rgb(230, 124, 115),
		"Work"::rgb(66, 133, 244),
		"Education"::rgb(244, 180, 0),
		"Others"::rgb(15, 157, 88)
	];


	
	map<string, string> survey_mode_to_acronym <- [
		"Marche seule"::"W",
		"Vélo"::"B",
		"Scooter - conducteur"::"SD",
		"Scooter - passager"::"SP",
		"Voiture - conducteur"::"CD",
		"Voiture - passager"::"CP",
		"Bus"::"BUS",
		"Métro"::"MTR",
		"Taxi"::"CTX",
		"Moto-taxi"::"STX",
		"PT"::"PT"
	];
	
	map<string, string> survey_purpose_to_english <- [
		"Domicile"::"Home",
		"Maison"::"Home",
		"Home"::"Home",
		"Achat"::"Shop",
		"Shop"::"Shop",
		"Travail 1"::"Work",
		"Travail 2"::"Work",
		"Affaires pro"::"Work",
		"Work"::"Work",
		"École"::"Education",
		"cole"::"Education",
		"Ecole"::"Education",
		"Education"::"Education",
		"Autre"::"Others",
		"Others"::"Others"
	];

	string translate_purpose(string p) {
		if (p = nil or p = "") { return "Home"; }
		if (p in survey_purpose_to_english.keys) {
			return survey_purpose_to_english[p];
		}
		if (p contains "cole" or p contains "Ecole" or p contains "ducat") {
			return "Education";
		}
		if (p contains "Travail" or p contains "Affaires") {
			return "Work";
		}
		if (p contains "Achat") {
			return "Shop";
		}
		if (p contains "Domicile" or p contains "Maison") {
			return "Home";
		}
		return "Others";
	}
	
	//  mode distribution
	map<string,int> mode_distribution_utility <- ["SD"::0, "SP"::0, "STX"::0, "CD"::0, "CP"::0, "CTX"::0, "MTR"::0, "BUS"::0, "W"::0, "B"::0, "PT"::0];
	

	
	float max_density <- 0.0;
	
	//UX/UI INTERACTION	
	bool display_person <- true;
	bool display_road <- true;
	bool display_metro <- false;
	bool display_bus <- false;
	bool display_water<-true;
	bool display_failed_destinations <- false;
	bool display_counting_points<-false;
	bool display_survey<-true;
	bool display_landuse <- true;
	bool display_anchors <- false;
	bool display_legend<-true;
	bool display_ux_legend<-true;
	bool display_legend_debug<-false;
	bool display_mode<-true;
	bool display_network<-true;
	bool drawAsArc<-true;
	string whatToVisualize;
	int person_id_to_inspect;
	string mode_to_display<-"none";
	rgb color<-rgb("#1F4E5F");
	bool IS_END <- false;
	bool darkmode<-false;
	bool display_overlay<-true;
	rgb text_color<-darkmode ? #white : #black;
	rgb background_color<-darkmode ? #black : #white;
	font titleFont<-font("Helvetica", 30,#plain);
	font textFont<-font("Helvetica", 18,#plain);
	font chartLegendFont<-font("Helvetica", 22,#plain);
	font simulationFont<-font("Helvetica",12,#plain);
	map<string, rgb> mobility_color <- [
		"W"::rgb("#BC7891"),
		"B"::rgb("#8AA154"),
		"S"::rgb("#CBA849"),
		"C"::rgb("#AA4140"),
		"BUS"::rgb("#2E799F"),
		"MTR"::rgb("#61A69B"),
		"PT"::rgb("#1F4E5F"),
		"area"::rgb("#2E799F"),
		"water"::rgb("#2E799F"),
		"road"::rgb("#4C4C4C")+100
	];

	map<string,rgb> metro_color <- [
    "1_0"  :: rgb(63,82,159),
    "1_1"  :: rgb(63,82,159),
    "2_0"  :: rgb(84,175,88),
    "2_1"  :: rgb(84,175,88),
    "3_0"  :: rgb(227,131,60),
    "3_1"  :: rgb(227,131,60),
    "4_0"  :: rgb(167,48,52),
    "4_1"  :: rgb(167,48,52),
    "5_0"  :: rgb(218,57,50),
    "5_1"  :: rgb(218,57,50),
    "6_0"  :: rgb(102,83,156),
    "6_1"  :: rgb(102,83,156),
    "7_0"  :: rgb(172,99,53),
    "7_1"  :: rgb(172,99,53),
    "8_0"  :: rgb(201,76,218),
    "8_1"  :: rgb(201,76,218),
    "10_0" :: rgb(200,54,112),
    "10_1" :: rgb(200,54,112),
    "11_0" :: rgb(78,40,103),
    "11_1" :: rgb(78,40,103)
];
	map<string, rgb> mode_color_legend <- ["Walk"::mobility_color["W"],"Bike"::mobility_color["B"],"Motorbike"::mobility_color["S"], "Car"::mobility_color["C"],  "Public transport"::mobility_color["PT"]];

	map<string, rgb> mode_color <- [
		"W"::mobility_color["W"],
		"B"::mobility_color["B"],
		"SD"::mobility_color["S"],
		"SP"::mobility_color["S"],
		"STX"::mobility_color["S"],
		"CD"::mobility_color["C"],
		"CP"::mobility_color["C"],
		"CTX"::mobility_color["C"],
		"PT"::mobility_color["PT"],
		"BUS"::mobility_color["BUS"],
		"MTR"::mobility_color["MTR"],
		"W_MTR"::mobility_color["W"],
		"W_BUS"::mobility_color["W"],
		"W_PT"::mobility_color["W"],
		"WAIT_BUS"::#red,
		"WAIT_MTR"::#red,
		"WAIT_PT"::#red,
		"à voir"::rgb("#BDBDBD")
	];



	
	//map<string, rgb> water_color <- ["riverbank"::rgb(31,120,180),"riverbanksecondary"::rgb(166,206,226),"water"::rgb(166,206,226)];
	map<string, rgb> natural_color <- ["riverbank"::rgb(30,59,67),"riverbanksecondary"::rgb(166,206,226),"water"::rgb(132,167,165),"park"::rgb(131,146,126),"boundary"::rgb(100,100,100),"boundary_province"::rgb(200,200,200)];
	

    float max_co2 <- 1.5;
	float max_km <- 13.0;
	float max_h <- 1.0;
	
	float max_instant_congestion <- 6.3;
	float max_total_congestion <- 2400.0;
   
	//map<string, rgb> mode_color <- ["Scooter - conducteur"::rgb("#FFA000"), "Scooter - passager"::rgb("#FFD54F"), "Voiture - conducteur"::rgb("#E64A19"), "Voiture - passager"::rgb("#F57C00"), "Vélo"::rgb("#8BC34A"), "Marche seule"::rgb("#757575"), "Métro"::rgb("#673AB7"), "Bus"::rgb("#1565C0"), "Taxi"::rgb("#42A5F5"), "Moto-taxi"::rgb("#42A5F5"), "à voir"::rgb("#BDBDBD")];
	list<rgb> pal <- palette([ #black, #green, #yellow, #orange, #orange, #red, #red, #red]);   
	//list<string> mode_list <- ["Scooter - conducteur", "Scooter - passager", "Voiture - conducteur", "Voiture - passager", "Vélo", "Marche seule", "Métro", "Bus", "Taxi", "Moto-taxi", "à voir"];
	//map<string, bool>
	//mode_vizu <- ["Scooter - conducteur"::true, "Scooter - passager"::true, "Voiture - conducteur"::true, "Voiture - passager"::true, "Vélo"::true, "Marche seule"::true, "Métro"::true, "Bus"::true, "Taxi"::true, "Moto-taxi"::true, "à voir"::true];
	     

	topology world_topology_graph;
	graph road_graph;
	graph road_graph_weighted_car;
	
	graph road_graph_weighted_scooter;
	
	graph road_graph_weighted_bike;
	
	graph bus_graph;
	graph bus_graph_weighted;
	graph metro_graph;
	graph metro_graph_weighted;
	graph multimodal_graph;
    graph multimodal_graph_weighted;
	
	float speed_voiture <- 4.50;
	float speed_scooter <- 4.70;
	float speed_velo <- 3.15;
	
	map<string, float> speed_by_mode <- [
        "BUS" :: 4.6,
        "W" :: 1.30,
        "W_MTR" :: 1.30,
        "W_BUS" :: 1.30,
        "W_PT" :: 1.30,
        "STX" :: speed_scooter,
        "MTR" :: 10.0,
        "SD" :: speed_scooter,
        "SP" :: speed_scooter,
        "CTX" :: speed_voiture,
        "CD" :: speed_voiture,
        "CP" :: speed_voiture,
        "B" :: speed_velo
    ];
    
    map<string, float> co2_factors_g_km <- [
        "CD"::142.0, "CP"::142.0, "CTX"::142.0,
        "SD"::76.3, "SP"::76.3, "STX"::76.3,
        "BUS"::122.0, "MTR"::4.44, "B"::0.17, "W"::0.0,
        "W_MTR"::0.0, "W_BUS"::0.0, "W_PT"::0.0
    ];

    map<string, float> pcu_by_mode <- [
        "CD"::1.2, "CP"::1.2, "CTX"::1.2,
        "SD"::0.25, "SP"::0.25, "STX"::0.25,
        "BUS"::0.1, "B"::0.15, "W"::0.0, "MTR"::0.0
    ];
   
   
   
//https://impactco2.fr/outils/transport


	// coef of sensititvity
    // Dictionaries for ASC and Beta by demographic status (Calibrated via MLE on HTS 2024 Survey)
    map<string, map<string, float>> asc_by_status <- [
        "Actif":: [
            "moto":: 0.0,
            "car":: -1.44,
            "bus":: -2.51,
            "metro":: -2.01,
            "walk":: -0.85,
            "bike":: -2.98
        ],
        "Étudiant ou élève":: [
            "moto":: 0.0,
            "car":: -2.64,
            "bus":: -0.24,
            "metro":: 0.26,
            "walk":: -0.30,
            "bike":: -3.66
        ],
        "Retraité":: [
            "moto":: 0.0,
            "car":: -1.59,
            "bus":: -1.51,
            "metro":: -1.01,
            "walk":: 0.37,
            "bike":: -1.58
        ],
        "Personne au foyer":: [
            "moto":: 0.0,
            "car":: -1.90,
            "bus":: -1.42,
            "metro":: -0.92,
            "walk":: -0.46,
            "bike":: -1.47
        ],
        "Sans emploi":: [
            "moto":: 0.0,
            "car":: -2.71,
            "bus":: -10.00,
            "metro":: -9.50,
            "walk":: -1.16,
            "bike":: -10.00
        ]
    ];
    
    map<string, float> beta_time_by_status <- [
        "Actif":: -0.0971,
        "Étudiant ou élève":: -0.1333,
        "Retraité":: -0.0623,
        "Personne au foyer":: -0.0234,
        "Sans emploi":: -0.0200
    ];
    
    map<string, float> beta_cost_by_status <- [
        "Actif":: -0.000000,
        "Étudiant ou élève":: -0.000201,
        "Retraité":: -0.000000,
        "Personne au foyer":: -0.000017,
        "Sans emploi":: -0.000000
    ];

    list<string> mode_affected_by_congestion <- ["BUS", "STX", "SD", "SP", "CTX", "CD", "CP", "B"];
    list<string> walk_modes <- ["W_MTR", "W_BUS", "W_PT", "W"];
    list<string> transit_modes <- ["BUS", "MTR"];
    list<string> wait_modes <- ["WAIT_BUS", "WAIT_MTR", "WAIT_PT"];
    list<string> pt_main_modes <- ["BUS", "MTR", "PT"];
    list<string> car_modes <- ["CD", "CP", "CTX"];
    list<string> moto_modes <- ["SD", "SP", "STX"];
    list<string> heavy_slowdown_modes <- ["CD", "CP", "CTX", "BUS"];
		
	float max_congestion_density <- 50.0;
	float max_slowdown_factor <- 0.7;
	float max_slowdown_car <- 0.88;
	float heatmap_retention <- 0.3;
	float base_scale_factor <- 50.0;
	float congestion_scale_factor;

	action load_calibration_parameters(string calib_path) {
		if (file_exists(calib_path)) {
			write ">>> [CALIBRATION] Loading parameters from: " + calib_path;
			file f <- csv_file(calib_path, ",", string, true);
			matrix m <- matrix(f);
			int n_rows <- m.rows;
			loop i from: 0 to: n_rows - 1 {
				string csp <- string(m[0, i]);
				string p_name <- string(m[1, i]);
				float p_val <- float(m[2, i]);
				
				// Normalisation : accepte les noms sans accents écrits par Python sur Windows
				if (csp = "Etudiant ou eleve" or csp contains "tudiant") {
					csp <- "Étudiant ou élève";
				} else if (csp = "Retraite" or (csp contains "Retrait" and !(csp contains "é"))) {
					csp <- "Retraité";
				}
				
				if (p_name = "lambda_hunger") {
					if (csp in lambda_need_rates_by_status.keys) {
						lambda_need_rates_by_status[csp]["hunger"] <- p_val;
					}
				} else if (p_name = "lambda_shop") {
					if (csp in lambda_need_rates_by_status.keys) {
						lambda_need_rates_by_status[csp]["shop"] <- p_val;
					}
				} else if (p_name = "lambda_leisure") {
					if (csp in lambda_need_rates_by_status.keys) {
						lambda_need_rates_by_status[csp]["leisure"] <- p_val;
					}
				} else if (p_name = "stay_on_site_work_hunger") {
					stay_on_site_utility_work["hunger"] <- p_val;
				} else if (p_name = "stay_on_site_work_shop") {
					stay_on_site_utility_work["shop"] <- p_val;
				} else if (p_name = "stay_on_site_work_leisure") {
					stay_on_site_utility_work["leisure"] <- p_val;
				} else if (p_name = "stay_on_site_edu_hunger") {
					stay_on_site_utility_edu["hunger"] <- p_val;
				} else if (p_name = "stay_on_site_edu_shop") {
					stay_on_site_utility_edu["shop"] <- p_val;
				} else if (p_name = "stay_on_site_edu_leisure") {
					stay_on_site_utility_edu["leisure"] <- p_val;
				} else if (p_name = "stay_at_home_hunger") {
					stay_at_home_utility["hunger"] <- p_val;
				} else if (p_name = "stay_at_home_shop") {
					stay_at_home_utility["shop"] <- p_val;
				} else if (p_name = "stay_at_home_leisure") {
					stay_at_home_utility["leisure"] <- p_val;
				} else if (p_name = "midday_home_lunch_utility") {
					midday_home_lunch_utility <- p_val;
				} else if (p_name = "hunger_shop_penalty") {
					hunger_shop_penalty <- p_val;
				} else if (p_name = "lunch_duration_mean_min") {
					lunch_duration_mean_min <- p_val;
				} else if (p_name = "onsite_lunch_duration_mean_min") {
					onsite_lunch_duration_mean_min <- p_val;
				} else if (p_name = "prob_worker_afternoon_shift") {
					prob_worker_afternoon_shift <- p_val;
				} else if (p_name = "prob_student_afternoon_shift") {
					prob_student_afternoon_shift <- p_val;
				} else if (p_name = "prob_student_morning_halfday") {
					prob_student_morning_halfday <- p_val;
				} else if (p_name = "work_duration_lognormal_mu") {
					work_duration_lognormal_mu <- p_val;
				} else if (p_name = "work_duration_lognormal_sigma") {
					work_duration_lognormal_sigma <- p_val;
				} else if (p_name = "work_dep_mean_hour") {
					work_dep_mean_hour <- p_val;
				} else if (p_name = "work_dep_std_hour") {
					work_dep_std_hour <- p_val;
				} else if (p_name = "edu_dep_mean_hour") {
					edu_dep_mean_hour <- p_val;
				} else if (p_name = "edu_dep_std_hour") {
					edu_dep_std_hour <- p_val;
				} else if (p_name = "daylight_urge_hunger") {
					daylight_urge_hunger <- p_val;
				} else if (p_name = "daylight_urge_leisure") {
					daylight_urge_leisure <- p_val;
				} else if (p_name = "seed" or p_name = "simulation_seed") {
					seed <- p_val;
					write ">>> [SEED] Simulation random seed initialized to: " + seed;
				}
			}
			write ">>> [CALIBRATION] Calibration parameters loaded successfully!";
		} else {
			write ">>> [CALIBRATION] No calibration file at " + calib_path + " - using default parameters.";
		}
	}
}


