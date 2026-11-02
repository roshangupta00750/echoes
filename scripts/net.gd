class_name Net extends Node
## LAN play: ENet for the match, and UDP broadcasts so players can find a host without typing an address.
## The host also shows its address, for networks (and some phones) that drop broadcasts.

const PORT := 47010
const DISC_PORT := 47011
const MAGIC := "ECHOES1"

var peer: ENetMultiplayerPeer
var disc: PacketPeerUDP
var hosting := false
var listening := false
var hosts := {}                    # ip -> {name, n, open, seen}
var announce_at := 0.0
var info := {"name": "HOST", "n": 1, "open": true}

func host() -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 7)
	if err != OK: peer = null; return err
	multiplayer.multiplayer_peer = peer
	hosting = true
	disc = PacketPeerUDP.new(); disc.set_broadcast_enabled(true)
	return OK

func join(ip: String) -> Error:
	close_peer()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK: peer = null; return err
	multiplayer.multiplayer_peer = peer
	return OK

func listen() -> void:
	if listening: return
	disc = PacketPeerUDP.new()
	# with broadcast on, Godot takes Android's multicast lock, without which many phones drop the hosts' calls
	disc.set_broadcast_enabled(true)
	if disc.bind(DISC_PORT) == OK: listening = true
	hosts.clear()

func stop_listen() -> void:
	if listening and disc: disc.close()
	listening = false

func close_peer() -> void:
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null

func close() -> void:
	close_peer()
	if disc: disc.close()
	disc = null; hosting = false; listening = false; hosts.clear()

func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."): continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."): out.append(a)
	return out

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if hosting and disc and now > announce_at:
		announce_at = now + 1.0
		var msg := ("%s|%s|%d|%d" % [MAGIC, info["name"], int(info["n"]), 1 if info["open"] else 0]).to_utf8_buffer()
		var targets := ["255.255.255.255"]
		for a in local_ips():
			var p: PackedStringArray = a.split(".")
			targets.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
		for t in targets:
			disc.set_dest_address(t, DISC_PORT); disc.put_packet(msg)
	if listening and disc:
		while disc.get_available_packet_count() > 0:
			var pkt := disc.get_packet().get_string_from_utf8()
			var ip := disc.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 4 and parts[0] == MAGIC and ip != "":
				hosts[ip] = {"name": parts[1], "n": int(parts[2]), "open": parts[3] == "1", "seen": now}
		for ip in hosts.keys():
			if now - float(hosts[ip]["seen"]) > 4.0: hosts.erase(ip)
