import 'product.dart';

/// Small in-memory LRU of products the user just tapped.
///
/// [ProductCard] remembers the product before opening its page, so the
/// detail screen can paint the image/title/price instantly (and run the hero
/// flight) while the full `ProductDetail` loads. Deep links simply miss.
abstract final class ProductPreviewCache {
  static const _max = 60;
  static final _items = <int, ProductSummary>{};

  static void remember(ProductSummary product) {
    _items.remove(product.id);
    _items[product.id] = product;
    if (_items.length > _max) _items.remove(_items.keys.first);
  }

  static void rememberAll(Iterable<ProductSummary> products) => products.forEach(remember);

  /// Looks up by numeric id or slug.
  static ProductSummary? lookup(String idOrSlug) {
    final id = int.tryParse(idOrSlug);
    if (id != null) return _items[id];
    for (final p in _items.values) {
      if (p.slug == idOrSlug) return p;
    }
    return null;
  }

  /// Hero tag shared by product images in grids and the detail gallery.
  static String heroTag(int productId) => 'product-image-$productId';
}
