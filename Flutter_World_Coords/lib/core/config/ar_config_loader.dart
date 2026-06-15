import 'dart:convert';
import 'package:flutter/services.dart';
import '../ar/models/anchor_blueprint.dart';
import '../ar/models/poi_model.dart';

// Load and validate AR configuration from bundled JSON assets.
// Decouples asset parsing from business logic - cubit calls this once on init.
class ARConfigLoader {
  static const _anchorBlueprintPath = 'assets/config/anchor_blueprint.json';
  static const _poiConfigPath = 'assets/config/poi_config.json';

  // Load all anchor blueprints from the bundled JSON asset.
  Future<List<AnchorBlueprint>> loadAnchors() async {
    final raw = await rootBundle.loadString(_anchorBlueprintPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['anchors'] as List;
    return list
        .map((e) => AnchorBlueprint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Load all POI definitions from the bundled JSON asset.
  Future<List<POIModel>> loadPOIs() async {
    final raw = await rootBundle.loadString(_poiConfigPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = json['pois'] as List;
    return list
        .map((e) => POIModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
