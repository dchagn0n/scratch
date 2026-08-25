#' Time to Live
max_TTL = 255 # bits
recommended_TTL = 64 # bits


#' Speed
speed_light = 299792458 #m/s
speed_fiber = 0.69 * speed_light #m/s


#' Link Length
min_link_length = 500000 # m # = 500 km
max_link_length = 500000 # m #3 * 10^6 # m # = 3000km # 10 000 km pour la russie
max_submarin_length = 3.9 * 10^7 # m = 39 000 km
min_submarin_length = 5 * 10^6 # m = 5 000 km
#increase transatlantic cable length by 5 000 km: 5 000, 10 000, 15 000km

#' Transmission rate
min_trans_rate = 1*10^9 #1Gbit/s ##5.6 * 10^4 #b/s = 56 kbit/s # mettre 1Gbit/s
max_trans_rate =  1*10^9 #1.59 * 10^11 #b/s = 159.253 Gbit/s # mettre 10 Gbit/s


#' Packet size in bits for BGP
min_packet_size = 160 #b = 20 bytes
max_packet_size_IP = 524280#b = 65 535 bytes for IP
max_packet_size = 32000# b = 4000 bytes
mean_min_packet_size = 4608#b = 500 bytes
mean_max_packet_size = 12000#b = 1500 bytes

min_img = 16000#b = 2B
max_img = 8*10^6#b = 10^6B
min_doc = 32000#b = 4000B
max_doc = 720000#b = 90 000B
min_media = 8*10^6#b = 10^6B
max_media = 4*10^7 #b = 5MB
min_movie = 3.2* 10^10#b = 4GB
max_movie = 2*10^11 #b = 2 10^10B = 25 GB



min_flow_img = floor(min_img / mean_max_packet_size)
max_flow_img = floor(max_img / mean_max_packet_size)

min_flow_doc = floor(min_doc / mean_max_packet_size)
max_flow_doc = floor(max_doc / mean_max_packet_size)

min_flow_media = floor(min_media / mean_max_packet_size)
max_flow_media = floor(max_media / mean_max_packet_size)

min_flow_movie = floor(min_movie / mean_max_packet_size)
max_flow_movie = floor(max_movie / mean_max_packet_size)

# packet per day
domestic_routeur = 120000 #paquets par jour , ie. 5000 paquets par heure
millions_routeur = 2000000
company_routeur = 50000000 # paquet/jour, ie. 1000 utilisateurs qui envoient entre 10000 et 100000 paquets par jour
datacenter_routeur= 1*10^9 # des milliards de paquets par jours

# Flow size
min_flow = 1 # min(min_flow_doc, min_flow_img, min_flow_media, min_flow_movie) # 100 #packets
alpha = 1.2 # ref : https://www.researchgate.net/publication/329555177_Synthetic_Trace_Generation_for_the_Internet_An_Integrated_Model#pf4
max_flow = 10000 #max(max_flow_doc, max_flow_img, max_flow_media, max_flow_movie) #10000 #packets


arrival_rate = 0.0001
service_rate = 0.001

