// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return '続行することで、$termsおよび$privacyに同意したものとみなされます。';
  }

  @override
  String get termsOfService => '利用規約';

  @override
  String get privacyPolicy => 'プライバシーポリシー';

  @override
  String get andLabel => 'と';

  @override
  String get theme => 'テーマ';

  @override
  String get themeTooltip => 'ライト/ダークテーマ';

  @override
  String get logging => 'ログ';

  @override
  String get reportIssue => '問題を報告';

  @override
  String get sourceCode => 'ソースコード';

  @override
  String get desktopApp => 'デスクトップアプリ';

  @override
  String get mobileApp => 'モバイルアプリ';

  @override
  String get leaveReview => 'レビューを書く';

  @override
  String get share => '共有';

  @override
  String get versionLabel => 'バージョン: ';

  @override
  String get loading => '読み込み中...';

  @override
  String get signOut => 'サインアウト';

  @override
  String get settingsPageTitle => '設定';

  @override
  String get language => '言語';

  @override
  String get tapToSelect => 'タップして選択';

  @override
  String get appTagline => 'あなたのプライベートファイルを運ぶフェリー';

  @override
  String get onboardingPurposeDescription =>
      'オープンソースで構築された、ゼロトラスト設計のクラウドストレージサービスです。データは端末を離れる前にローカルで暗号化されます。';

  @override
  String get failedToFetch => '取得に失敗しました。';

  @override
  String get supportedStorageTitle => '対応ストレージ';

  @override
  String get supportedStorageDescription =>
      'よく使うプロバイダーを接続できます。まずはFiFe標準の安全な無料ストレージ1 GBですぐに始められます。';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'すぐにバックアップ開始';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => '無料';

  @override
  String get providerStorageDisclaimer =>
      '* 無料容量は各プロバイダーのWebサイト記載内容に基づきます。対応プロバイダーでは従量課金も利用できます。';

  @override
  String get whyUseFifeTitle => 'FiFeを使う理由';

  @override
  String get claimFreeCloudStorageTitle => '無料のクラウド容量を活用';

  @override
  String get claimFreeCloudStorageDescription =>
      '複数のクラウドプロバイダーを接続して容量を最大限に活用できます。各社の無料枠を1つのアプリで安全にまとめて使えます。';

  @override
  String get topNotchSecurityTitle => '高水準のセキュリティ';

  @override
  String get topNotchSecurityDescription =>
      '高度なSodium暗号技術を採用。暗号化も復号も、すべて端末上でローカルに実行されます。';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'すべてのクラウドストレージプロバイダー上で、データの主導権を自分で保てます。自分のアカウントで暗号化ストレージを利用できます。';

  @override
  String get payAsYouGoStorageTitle => 'ストレージは使った分だけ。';

  @override
  String get payAsYouGoStorageDescription =>
      '対応プロバイダーでは、使ったストレージ分だけ支払います。仲介なし、データの囲い込みもありません。';

  @override
  String get zeroKnowledgePrivacyTitle => 'ゼロ知識プライバシー';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'データは送信前に端末上で保護されます。私たちがファイルを見たり、読んだり、スキャンしたりすることはできません。';

  @override
  String get localSelectionTitle => '1. ローカルで選択';

  @override
  String get localSelectionDescription => 'フォルダーを選択すると、すべての処理が端末上で安全に開始されます。';

  @override
  String get metadataEncryptionTitle => '2. メタデータを暗号化';

  @override
  String get metadataEncryptionDescription =>
      'ファイル名、種類、サイズなどの情報は、サーバーへ送信される前に暗号化されます。';

  @override
  String get contentEncryptionTitle => '3. コンテンツを暗号化';

  @override
  String get contentEncryptionDescription =>
      '実際のファイル内容は分割され、暗号化されたうえでクラウドストレージにアップロードされます。';

  @override
  String get blindServerTitle => '4. 中身を知らないサーバー';

  @override
  String get blindServerDescription =>
      'サーバーはデータの内容を知りません。見えるのは暗号化されたデータ片だけなので、高いプライバシーが保たれます。';

  @override
  String get dontTrustVerifyTitle => '信じるだけでなく、確かめてください。';

  @override
  String get openSourceVerificationDescription =>
      '100%オープンソースです。ファイルがどのように暗号化されるか、コードを確認できます。';

  @override
  String get getStarted => '始める';

  @override
  String get next => '次へ';

  @override
  String get unauthorized => '認証されていません';

  @override
  String get tryAgain => '再試行';

  @override
  String get errorTitle => 'エラー';

  @override
  String get failureTitle => '失敗';

  @override
  String get invalidWordList => '無効な単語リストです';

  @override
  String get invalidAccessKey => '無効なアクセスキーです';

  @override
  String get unexpectedDecryptionError => '復号中に予期しないエラーが発生しました。';

  @override
  String get fileMustContainExactly24Words => 'ファイルには24語ちょうど含まれている必要があります。';

  @override
  String get errorReadingFile => 'ファイルの読み込みエラー';

  @override
  String get encryptionTitle => '暗号化';

  @override
  String get accessKeyDecodeDescription =>
      '24語の復元フレーズを入力するか、.txtファイルを読み込んで、安全にクラウド同期を有効にしてください。';

  @override
  String get recoveryPhraseLabel => '復元フレーズ';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => '貼り付け';

  @override
  String wordCountLabel(int count) {
    return '$count / 24語';
  }

  @override
  String get pleaseEnterRecoveryPhrase => '復元フレーズを入力してください';

  @override
  String get mustContainExactly24Words => '24語ちょうど入力してください';

  @override
  String get verify => '確認';

  @override
  String get orLabel => 'または';

  @override
  String get loadFromTxtFile => '.txtファイルから読み込む';

  @override
  String get saveAccessKey => 'アクセスキーを保存';

  @override
  String get fileSavedSuccessfully => 'ファイルを保存しました。';

  @override
  String get accessKeyShareMessage => 'こちらがアクセスキーです。';

  @override
  String get pleaseTryAgain => 'もう一度お試しください。';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get accessKeyTitle => 'アクセスキー';

  @override
  String get accessKeyDescription =>
      'このキーは安全な場所に保管してください。暗号化されたデータにアクセスできるのはこのキーだけです。';

  @override
  String get copy => 'コピー';

  @override
  String get downloadAsTextFile => 'テキストファイルとして保存';

  @override
  String get continueLabel => '続行';

  @override
  String get importantTitle => '重要';

  @override
  String get accessKeyNoticePrimary =>
      '次のページには24個の単語が表示されます。これはあなた専用の秘密の暗号化キーであり、ログアウト、端末の紛失、故障時にデータを復元するための唯一の方法です。';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'このキーは私たちでは保管していません。$appNameアプリの外にある安全な場所へ保存するのは、あなた自身の責任です。';
  }

  @override
  String get showKeyConfirmation => '理解しました。\nキーを表示する';

  @override
  String get storageAddedSuccessfully => 'ストレージを追加しました';

  @override
  String get networkErrorDuringValidation => '検証中にネットワークエラーが発生しました。';

  @override
  String get verifyAndConnect => '確認して接続';

  @override
  String get requiredField => '必須です';

  @override
  String get providerKeysVerifiedLocally => 'キーはローカルで検証され、送信前に暗号化されます。';

  @override
  String get enterYourCredentials => '認証情報を入力してください';

  @override
  String connectProvider(String provider) {
    return '$providerに接続';
  }

  @override
  String get deviceLimitReached => 'デバイス上限に達しました';

  @override
  String get pleaseTryAgainWithExclamation => 'もう一度お試しください!';

  @override
  String get notThisDevice => 'このデバイスは対象外です!';

  @override
  String get confirmSignoutDeviceTitle => 'デバイスのサインアウト確認';

  @override
  String get areYouSure => 'よろしいですか?';

  @override
  String get cancel => 'キャンセル';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'デバイスが見つかりません';

  @override
  String get backTooltip => '戻る';

  @override
  String get devicesTitle => 'デバイス';

  @override
  String get longPressToDownload => '長押しでダウンロード';

  @override
  String get fewItemsExistLocally => '一部の項目はローカルに残っています。';

  @override
  String selectedItemsCount(int count) {
    return '$count件を選択中';
  }

  @override
  String get delete => '削除';

  @override
  String get info => '情報';

  @override
  String get download => 'ダウンロード';

  @override
  String get archive => 'アーカイブ';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'ログ';

  @override
  String get settings => '設定';

  @override
  String get trash => 'ゴミ箱';

  @override
  String get storage => 'ストレージ';

  @override
  String get search => '検索';

  @override
  String get database => 'データベース';

  @override
  String get addFolderTitle => 'フォルダーを追加';

  @override
  String get confirm => '確認';

  @override
  String get tapPlusToAddSyncFolder => '+ をタップして同期フォルダーを追加してください。';

  @override
  String get thisFolderIsEmpty => 'このフォルダーは空です。';

  @override
  String get fileNotFound => 'ファイルが見つかりません';

  @override
  String filePartsTitle(int count) {
    return 'ファイル分割数 ($count)';
  }

  @override
  String get fileDetailsTitle => 'ファイル詳細';

  @override
  String get encryptedBackup => '暗号化バックアップ';

  @override
  String get sizeLabel => 'サイズ';

  @override
  String get providerLabel => 'プロバイダー';

  @override
  String get uploadedAtLabel => 'アップロード日時';

  @override
  String get statusLabel => '状態';

  @override
  String get uploadedStatus => 'アップロード済み';

  @override
  String errorWithMessage(String message) {
    return 'エラー: $message';
  }

  @override
  String get noLogsAvailable => 'ログはありません';

  @override
  String get searchLogsHint => 'ログを検索...';

  @override
  String get clearLogs => 'ログを消去';

  @override
  String get searchWithMinThreeCharacters => '3文字以上入力して検索';

  @override
  String get typeBelowToSearch => '下に入力して検索';

  @override
  String get noResults => '結果がありません。';

  @override
  String get welcomeTitle => 'ようこそ';

  @override
  String signInToContinue(String appName) {
    return '$appNameを利用するにはサインインしてください';
  }

  @override
  String get pleaseEnterYourEmail => 'メールアドレスを入力してください';

  @override
  String get pleaseEnterValidEmailAddress => '有効なメールアドレスを入力してください';

  @override
  String get emailAddressLabel => 'メールアドレス';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'OTPを再送信';

  @override
  String get sendOtp => 'OTPを送信';

  @override
  String get checkYourEmail => 'メールを確認してください';

  @override
  String sentSixDigitCodeTo(String email) {
    return '6桁のコードを次の宛先へ送信しました\n$email';
  }

  @override
  String get pleaseEnterOtp => 'OTPを入力してください';

  @override
  String get otpMustBeSixDigits => 'OTPは6桁で入力してください';

  @override
  String get enterOtpLabel => 'OTPを入力';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => '認証を再試行';

  @override
  String get verifyOtp => 'OTPを確認';

  @override
  String get useDifferentEmail => '別のメールアドレスを使う';

  @override
  String get alreadySignedIn => 'すでにサインインしています';

  @override
  String get sendingOtpFailedPleaseTryAgain => 'OTPの送信に失敗しました。もう一度お試しください!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTPの確認に失敗しました。もう一度お試しください。';

  @override
  String get dbViewerTitle => 'DBビューア';

  @override
  String get selectTableToViewData => '表示するテーブルを選択してください';

  @override
  String get selectTable => 'テーブルを選択';

  @override
  String get permissionRequiredTitle => '権限が必要です';

  @override
  String get storagePermissionSettingsDescription =>
      'ファイルを自動でバックアップ・管理・保護するには、端末ストレージへのアクセスが必要です。データはローカルで暗号化されるため、プライバシーは守られます。続行するにはアクセスを許可してください。';

  @override
  String get openSettings => '設定を開く';

  @override
  String get storagePermissionRequiredToContinue => '続行するにはストレージ権限が必要です';

  @override
  String get secureLocalAccessTitle => '安全なローカルアクセス';

  @override
  String get storagePermissionPageDescription =>
      'ファイルの閲覧、暗号化、自動バックアップのために、端末ストレージへのアクセスが必要です。';

  @override
  String get verifying => '確認中...';

  @override
  String get grantAccess => 'アクセスを許可';

  @override
  String get zeroKnowledgeEncryptedStorage => 'ゼロ知識型の暗号化ストレージ';

  @override
  String requiresAppPro(String appName) {
    return '$appName Proが必要です。';
  }

  @override
  String get noStorageFound => 'ストレージが見つかりません';

  @override
  String get howToConnect => '接続方法';

  @override
  String get modify => '変更';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total 使用中';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return '最大$sizeまで無料';
  }

  @override
  String get notConnected => '未接続';

  @override
  String get connect => '接続';

  @override
  String get modifyStorageCapacityTitle => 'ストレージ容量を変更';

  @override
  String get enterNewStorageLimitForProvider => 'このプロバイダーの新しいストレージ上限を入力してください。';

  @override
  String get sizePrefix => 'サイズ: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'サイズを入力してください';

  @override
  String get enterValidNumberGreaterThanOne => '1より大きい有効な数値を入力してください';

  @override
  String get submit => '送信';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '$appName Proの購読が完了しました!';
  }

  @override
  String get purchaseCancelledOrFailed => '購入はキャンセルされたか、失敗しました。';

  @override
  String get purchasesRestoredSuccessfully => '購入を復元しました!';

  @override
  String get noActiveSubscriptionsFound => '有効なサブスクリプションが見つかりません。';

  @override
  String get manageSubscriptionsInDeviceSettings => 'サブスクリプションは端末の設定で管理してください。';

  @override
  String get freePlanTitle => '無料';

  @override
  String get freeForeverPrice => '\$0.00 / 永久無料';

  @override
  String get freeBenefitProviderStorage => '各プロバイダーの無料ストレージを活用';

  @override
  String get freeBenefitSyncThreeDevices => '最大3台のデバイスを安全に同期';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - 年額';
  }

  @override
  String get proBenefitModifyStorageLimit => '各プロバイダーのストレージ上限を変更可能';

  @override
  String get proBenefitSyncTenDevices => '最大10台まで同期';

  @override
  String get restorePurchases => '購入を復元';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* サブスクリプションはデバイスではなくメールアカウントに紐づきます';

  @override
  String get subscriptionExpiredTitle => 'サブスクリプションの期限切れ';

  @override
  String subscriptionExpiredDescription(String appName) {
    return '$appName Proの特典は現在停止中です。下から更新すると、ストレージ上限とデバイス同期を再び利用できます。';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Proは有効です';
  }

  @override
  String get activePlanBenefitsSummary => '✓ 各プロバイダーのストレージ上限を変更\n✓ 最大10台まで相互同期';

  @override
  String get manageSubscription => 'サブスクリプションを管理';

  @override
  String get currentPlanBadge => '現在のプラン';

  @override
  String get subscribeNow => '今すぐ購読';

  @override
  String get subscribeOnMobileApp => 'モバイルアプリで購読';

  @override
  String get recover => '復元';

  @override
  String get empty => '空にする';

  @override
  String get noItems => '項目がありません。';
}
