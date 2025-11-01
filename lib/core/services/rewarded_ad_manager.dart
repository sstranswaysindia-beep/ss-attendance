import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const String _kAndroidRewardedAdUnitId =
    String.fromEnvironment('ANDROID_REWARDED_AD_UNIT_ID');
const String _kIosRewardedAdUnitId =
    String.fromEnvironment('IOS_REWARDED_AD_UNIT_ID');

class RewardedAdManager {
  RewardedAdManager({AdRequest? request}) : _request = request ?? const AdRequest();

  final AdRequest _request;

  static String get _adUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _kAndroidRewardedAdUnitId.isNotEmpty
          ? _kAndroidRewardedAdUnitId
          : 'ca-app-pub-3940256099942544/5224354917';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _kIosRewardedAdUnitId.isNotEmpty
          ? _kIosRewardedAdUnitId
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return '';
  }

  Future<void> showRewardedAd({
    required Future<void> Function() onRewarded,
    required void Function(String message) onError,
  }) async {
    if (kIsWeb) {
      onError('Rewarded ads are not supported on web.');
      return;
    }

    final adUnitId = _adUnitId;
    if (adUnitId.isEmpty) {
      onError('Unsupported platform for rewarded ads.');
      return;
    }

    final completer = Completer<void>();
    bool hasRewarded = false;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: _request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!hasRewarded) {
                onError('Ad closed before reward was earned.');
              }
              if (!completer.isCompleted) completer.complete();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              onError('Ad failed to show: ${error.message}');
              if (!completer.isCompleted) completer.complete();
            },
          );

          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
              hasRewarded = true;
              try {
                await onRewarded();
              } catch (error) {
                onError(error.toString());
              }
              if (!completer.isCompleted) completer.complete();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          onError('Unable to load ad: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );

    await completer.future;
  }
}
