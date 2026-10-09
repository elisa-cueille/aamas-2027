/**
* Name: roadBus
* Unified edge species for the combined road+bus graph.
* type = "road"      : road network edges
* type = "bus"       : bus line edges
* type = "connector" : boarding/alighting edges linking road <-> bus
*/

model road_bus

import 'public_transport.gaml'
species road_bus parent: public_transport{
}
