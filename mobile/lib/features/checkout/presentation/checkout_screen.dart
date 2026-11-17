import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/data/models/cart.dart';
import '../../cart/presentation/widgets/cart_summary.dart';
import '../../cart/providers/cart_controller.dart';
import '../../notifications/providers/notifications_providers.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/providers/orders_providers.dart';
import '../../profile/data/models/address.dart';
import '../../profile/presentation/widgets/address_form.dart';
import '../../profile/providers/profile_providers.dart';
import 'widgets/card_utils.dart';

enum _Payment { cod, card }

/// Single-page checkout: 1 address · 2 payment · 3 notes · 4 review, then
/// "Place order". Only the card's last 4 digits are sent to the server.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _cardForm = GlobalKey<FormState>();
  final _cardNumber = TextEditingController();
  final _cardName = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _notes = TextEditingController();

  int? _addressId;
  bool _addingAddress = false;
  _Payment _payment = _Payment.cod;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cardNumber.addListener(() => setState(() {})); // brand badge
  }

  @override
  void dispose() {
    for (final c in [_cardNumber, _cardName, _expiry, _cvv, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  CardBrand get _brand => CardBrand.detect(CardValidators.digitsOf(_cardNumber.text));

  Address? _selectedAddress(List<Address> list) {
    if (list.isEmpty) return null;
    for (final a in list) {
      if (a.id == _addressId) return a;
    }
    return list.firstWhere((a) => a.isDefault, orElse: () => list.first);
  }

  Future<void> _placeOrder(Cart cart, List<Address> addresses) async {
    final address = _selectedAddress(addresses);
    setState(() => _error = null);
    if (address == null) {
      setState(() => _error = 'Add a delivery address to continue.');
      return;
    }
    if (_payment == _Payment.card && !(_cardForm.currentState?.validate() ?? false)) {
      setState(() => _error = 'Check your card details.');
      return;
    }
    if (cart.unavailable.isNotEmpty) {
      setState(() => _error = 'Some items are out of stock. Remove them from your cart first.');
      return;
    }
    context.unfocus();
    setState(() => _placing = true);
    try {
      final digits = CardValidators.digitsOf(_cardNumber.text);
      final order = await ref
          .read(ordersRepositoryProvider)
          .place(
            addressId: address.id,
            paymentMethod: _payment.name,
            cardLast4: _payment == _Payment.card ? digits.substring(digits.length - 4) : null,
            notes: _notes.text,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ref.read(cartProvider.notifier).markEmpty();
      ref.invalidate(ordersProvider);
      ref.invalidate(userStatsProvider);
      ref.read(unreadNotificationsProvider.notifier).refresh();
      context.pushReplacement(Routes.orderSuccessOf(order.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = e.message;
      });
      // stock / empty cart / coupon problems: show the cart as the server sees it
      if (e.isConflict || e.isValidation) ref.read(cartProvider.notifier).refresh().catchError((_) {});
      if (e.isNotFound) ref.invalidate(addressesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartAsync = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesProvider);
    final cart = cartAsync.value;
    final twoColumn = context.screenWidth >= 900;

    final Widget body;
    if (cart == null) {
      body = cartAsync.hasError
          ? ErrorState(error: cartAsync.error, onRetry: () => ref.invalidate(cartProvider))
          : const ResponsiveCenter(maxWidth: 720, child: SkeletonList(count: 5));
    } else if (cart.isEmpty) {
      body = EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Your cart is empty',
        message: 'Add something to your cart before checking out.',
        actionLabel: 'Continue shopping',
        onAction: () => context.go(Routes.home),
      );
    } else {
      final addresses = addressesAsync.value ?? const <Address>[];
      final steps = _steps(cart, addressesAsync);
      final summary = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SummaryCard(summary: cart.summary),
          const SizedBox(height: AppSpacing.md),
          FormErrorBanner(message: _error),
          AppButton(
            label: 'Place order · ${Formatters.price(cart.summary.total)}',
            icon: Icons.lock_outline_rounded,
            size: AppButtonSize.large,
            expand: true,
            loading: _placing,
            onPressed: addressesAsync.isLoading ? null : () => _placeOrder(cart, addresses),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'By placing your order you agree to our terms. Payments are simulated in this demo.',
            style: context.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      );

      body = twoColumn
          ? ResponsiveCenter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.only(bottom: AppSpacing.xxl), children: steps),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  SizedBox(
                    width: 380,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xl),
                      child: summary,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                ResponsiveCenter(
                  maxWidth: 720,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...steps, const SizedBox(height: AppSpacing.xl), summary],
                  ),
                ),
              ],
            );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: body,
    );
  }

  List<Widget> _steps(Cart cart, AsyncValue<List<Address>> addressesAsync) {
    return [
      _Step(
        number: 1,
        title: 'Delivery address',
        child: switch (addressesAsync) {
          AsyncValue(:final value?) => _addresses(value),
          AsyncValue(:final error?) => ErrorState(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(addressesProvider),
          ),
          _ => const SkeletonList(count: 2),
        },
      ),
      _Step(number: 2, title: 'Payment', child: _paymentSection()),
      _Step(
        number: 3,
        title: 'Order notes',
        subtitle: 'Optional',
        child: AppTextField(
          controller: _notes,
          hint: 'Delivery instructions, gate code, best time to call…',
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
        ),
      ),
      _Step(
        number: 4,
        title: 'Review items',
        subtitle: Formatters.plural(cart.summary.itemCount, 'item'),
        trailing: TextButton(onPressed: () => context.go(Routes.cart), child: const Text('Edit')),
        child: Column(children: [for (final i in cart.items) _ReviewLine(item: i)]),
      ),
    ];
  }

  Widget _addresses(List<Address> list) {
    final selected = _selectedAddress(list);
    if (list.isEmpty || _addingAddress) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadii.cardAll,
          border: Border.all(color: context.colors.border),
        ),
        child: AddressForm(
          submitLabel: 'Use this address',
          onCancel: list.isEmpty ? null : () => setState(() => _addingAddress = false),
          onSaved: (a) => setState(() {
            _addressId = a.id;
            _addingAddress = false;
          }),
        ),
      );
    }
    return RadioGroup<int>(
      groupValue: selected?.id,
      onChanged: (id) => setState(() => _addressId = id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _SelectableCard(
                selected: a.id == selected?.id,
                onTap: () => setState(() => _addressId = a.id),
                leading: Radio<int>(value: a.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(a.label ?? 'Address', style: context.textTheme.titleSmall),
                        if (a.isDefault) const _Tag('Default'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${a.fullName} · ${a.phone}', style: context.textTheme.bodyMedium),
                    Text(a.oneLine, style: context.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _addingAddress = true),
              style: TextButton.styleFrom(foregroundColor: context.colors.secondary),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a new address'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentSection() {
    final t = context.textTheme;
    final brand = _brand;
    return RadioGroup<_Payment>(
      groupValue: _payment,
      onChanged: (p) => setState(() => _payment = p ?? _Payment.cod),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SelectableCard(
            selected: _payment == _Payment.cod,
            onTap: () => setState(() => _payment = _Payment.cod),
            leading: const Radio<_Payment>(value: _Payment.cod),
            trailing: const Icon(Icons.payments_outlined),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cash on delivery', style: t.titleSmall),
                Text('Pay when your order arrives', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _SelectableCard(
            selected: _payment == _Payment.card,
            onTap: () => setState(() => _payment = _Payment.card),
            leading: const Radio<_Payment>(value: _Payment.card),
            trailing: const Icon(Icons.credit_card_rounded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Credit / debit card', style: t.titleSmall),
                Text('Visa, Mastercard, Amex, UnionPay', style: t.bodySmall),
              ],
            ),
          ),
          AnimatedSize(
            duration: context.motion(AppDurations.normal),
            alignment: Alignment.topCenter,
            child: _payment != _Payment.card
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Form(
                      key: _cardForm,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppTextField(
                              label: 'Card number',
                              controller: _cardNumber,
                              hint: '1234 5678 9012 3456',
                              prefixIcon: Icons.credit_card_rounded,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.creditCardNumber],
                              inputFormatters: [CardNumberFormatter()],
                              validator: CardValidators.number,
                              suffix: brand == CardBrand.unknown
                                  ? null
                                  : Padding(
                                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                                      child: Center(
                                        widthFactor: 1,
                                        child: _Tag(brand.label),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppTextField(
                              label: 'Name on card',
                              controller: _cardName,
                              autofillHints: const [AutofillHints.creditCardName],
                              textCapitalization: TextCapitalization.characters,
                              validator: Validators.required('Name on card'),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    label: 'Expiry',
                                    controller: _expiry,
                                    hint: 'MM/YY',
                                    keyboardType: TextInputType.number,
                                    autofillHints: const [AutofillHints.creditCardExpirationDate],
                                    inputFormatters: [ExpiryFormatter()],
                                    validator: (v) => CardValidators.expiry(v),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: AppTextField(
                                    label: 'CVV',
                                    controller: _cvv,
                                    hint: brand.cvvLength == 4 ? '4 digits' : '3 digits',
                                    keyboardType: TextInputType.number,
                                    isPassword: true,
                                    autofillHints: const [AutofillHints.creditCardSecurityCode],
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(brand.cvvLength),
                                    ],
                                    validator: (v) => CardValidators.cvv(v, brand),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 14, color: context.colors.muted),
                                const SizedBox(width: AppSpacing.xxs),
                                Expanded(
                                  child: Text(
                                    'Your full card number never leaves this device — only the last 4 digits are saved.',
                                    style: t.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child, this.subtitle, this.trailing});

  final int number;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.text, shape: BoxShape.circle),
                child: Text('$number', style: t.labelMedium!.copyWith(color: colors.background)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      children: [
                        if (subtitle != null)
                          TextSpan(text: '  $subtitle', style: t.bodySmall),
                      ],
                    ),
                    style: t.titleMedium,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.child,
    this.trailing,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.surfaceVariant : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardAll,
        side: BorderSide(color: selected ? colors.text : colors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: AppRadii.cardAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              leading,
              Expanded(child: child),
              if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.inputAll),
      child: Text(label, style: context.textTheme.labelSmall!.copyWith(color: colors.primary)),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final p = item.product;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          AppNetworkImage(p.thumbnail, width: 52, height: 52, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                Text(
                  p.inStock ? 'Qty ${item.quantity} × ${Formatters.price(p.price)}' : 'Out of stock',
                  style: t.bodySmall!.copyWith(color: p.inStock ? null : context.colors.error),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(Formatters.price(item.lineTotal), style: t.titleSmall),
        ],
      ),
    );
  }
}
