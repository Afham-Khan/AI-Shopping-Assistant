import 'package:material_ui/material_ui.dart';

/// Maps department/category slugs (or the API's `icon` names) to icons.
/// Unknown values fall back to a neutral icon, so new seed data never breaks UI.
abstract final class CategoryIcons {
  static const _bySlug = <String, IconData>{
    // departments
    'electronics': Icons.devices_outlined,
    'fashion': Icons.checkroom_outlined,
    'men': Icons.man_outlined,
    'mens-fashion': Icons.man_outlined,
    'women': Icons.woman_outlined,
    'womens-fashion': Icons.woman_outlined,
    'beauty-personal-care': Icons.spa_outlined,
    'home-living': Icons.chair_outlined,
    'home-kitchen': Icons.kitchen_outlined,
    'sports-outdoors': Icons.sports_basketball_outlined,
    'automotive': Icons.directions_car_outlined,
    'grocery': Icons.local_grocery_store_outlined,
    // categories
    'smartphones': Icons.smartphone_outlined,
    'laptops': Icons.laptop_mac_outlined,
    'tablets': Icons.tablet_mac_outlined,
    'mobile-accessories': Icons.headphones_outlined,
    'beauty': Icons.brush_outlined,
    'fragrances': Icons.local_florist_outlined,
    'skin-care': Icons.face_retouching_natural_outlined,
    'furniture': Icons.weekend_outlined,
    'home-decoration': Icons.light_outlined,
    'kitchen-accessories': Icons.soup_kitchen_outlined,
    'groceries': Icons.shopping_basket_outlined,
    'mens-shirts': Icons.dry_cleaning_outlined,
    'mens-shoes': Icons.hiking_outlined,
    'mens-watches': Icons.watch_outlined,
    'womens-dresses': Icons.checkroom_outlined,
    'womens-shoes': Icons.ice_skating_outlined,
    'womens-watches': Icons.watch_outlined,
    'womens-bags': Icons.shopping_bag_outlined,
    'womens-jewellery': Icons.diamond_outlined,
    'tops': Icons.dry_cleaning_outlined,
    'sunglasses': Icons.visibility_outlined,
    'sports-accessories': Icons.sports_tennis_outlined,
    'motorcycle': Icons.two_wheeler_outlined,
    'vehicle': Icons.directions_car_outlined,
  };

  // material icon names the backend may store in `departments.icon`
  static const _byName = <String, IconData>{
    'devices': Icons.devices_outlined,
    'smartphone': Icons.smartphone_outlined,
    'laptop': Icons.laptop_mac_outlined,
    'checkroom': Icons.checkroom_outlined,
    'spa': Icons.spa_outlined,
    'chair': Icons.chair_outlined,
    'home': Icons.home_outlined,
    'kitchen': Icons.kitchen_outlined,
    'sports': Icons.sports_basketball_outlined,
    'fitness': Icons.fitness_center_outlined,
    'car': Icons.directions_car_outlined,
    'directions_car': Icons.directions_car_outlined,
    'grocery': Icons.local_grocery_store_outlined,
    'shopping_basket': Icons.shopping_basket_outlined,
    'watch': Icons.watch_outlined,
    'diamond': Icons.diamond_outlined,
    'man': Icons.man_outlined,
    'woman': Icons.woman_outlined,
  };

  static IconData of(String? slugOrName) {
    if (slugOrName == null) return Icons.category_outlined;
    final key = slugOrName.trim().toLowerCase();
    return _bySlug[key] ??
        _byName[key] ??
        _byName[key.replaceAll('-', '_')] ??
        _fuzzy(key) ??
        Icons.category_outlined;
  }

  static IconData? _fuzzy(String key) {
    if (key.contains('phone')) return Icons.smartphone_outlined;
    if (key.contains('laptop') || key.contains('computer')) return Icons.laptop_mac_outlined;
    if (key.contains('watch')) return Icons.watch_outlined;
    if (key.contains('shoe')) return Icons.hiking_outlined;
    if (key.contains('beauty') || key.contains('care')) return Icons.spa_outlined;
    if (key.contains('home') || key.contains('decor')) return Icons.chair_outlined;
    if (key.contains('kitchen')) return Icons.kitchen_outlined;
    if (key.contains('sport')) return Icons.sports_basketball_outlined;
    if (key.contains('fashion') || key.contains('cloth')) return Icons.checkroom_outlined;
    if (key.contains('grocer') || key.contains('food')) return Icons.local_grocery_store_outlined;
    return null;
  }
}
