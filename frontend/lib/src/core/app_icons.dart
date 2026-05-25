import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// [TonztoonIcons] adalah pusat pengelolaan ikon di aplikasi.
/// Dengan menyatukan semua ikon di sini, jika di masa depan kita ingin
/// mengganti library ikon (misalnya dari Lucide ke Material), kita hanya perlu
/// mengubah file ini, tidak perlu mencari satu per satu di setiap layar.
class TonztoonIcons {
  const TonztoonIcons._();

  // Ikon-ikon utama
  static const IconData home = LucideIcons.house;
  static const IconData search = LucideIcons.search;
  static const IconData library = LucideIcons.library;
  static const IconData settings = LucideIcons.settings;
  static const IconData accountCircle = LucideIcons.circleUserRound;
  static const IconData login = LucideIcons.logIn;
  static const IconData logout = LucideIcons.logOut;
  static const IconData userPlus = LucideIcons.userPlus;

  // Ikon untuk pembaca / buku
  static const IconData menuBook = LucideIcons.bookOpen;
  static const IconData bookmark = LucideIcons.bookmark;
  static const IconData bookmarkFilled = Icons.bookmark_rounded;
  static const IconData bookmarkAdded = LucideIcons.bookmarkCheck;
  static const IconData heart = LucideIcons.heart;
  static const IconData star = LucideIcons.star;
  static const IconData starFilled = Icons.star_rounded;
  static const IconData play = LucideIcons.play;
  static const IconData download = LucideIcons.download;
  static const IconData cloudUpload = LucideIcons.cloudUpload;
  static const IconData share = LucideIcons.share2;
  static const IconData bookOpen = LucideIcons.bookOpen;

  // Ikon tambahan untuk Home
  static const IconData bell = LucideIcons.bell;
  static const IconData autoAwesome = LucideIcons.sparkles;
  static const IconData localFireDepartment = LucideIcons.flame;
  static const IconData travelExplore = LucideIcons.globe;
  static const IconData keyboardArrowDown = LucideIcons.chevronDown;

  // Ikon antarmuka umum
  static const IconData arrowBack = LucideIcons.arrowLeft;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData close = LucideIcons.x;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData moreHoriz = LucideIcons.ellipsis;
  static const IconData plus = LucideIcons.plus;
  static const IconData pencil = LucideIcons.pencil;
  static const IconData trash = LucideIcons.trash2;
  static const IconData check = LucideIcons.check;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData slidersHorizontal = LucideIcons.slidersHorizontal;
  static const IconData messageSquare = LucideIcons.messageSquare;
  static const IconData image = LucideIcons.image;
  static const IconData camera = LucideIcons.camera;
  static const IconData bookMarked = LucideIcons.bookMarked;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData clock = LucideIcons.clock;
  static const IconData eye = LucideIcons.eye;
  static const IconData list = LucideIcons.list;
  static const IconData tags = LucideIcons.tags;
  static const IconData user = LucideIcons.user;
  static const IconData paintbrush = LucideIcons.paintbrush;
  static const IconData badge = LucideIcons.badge;
  static const IconData rows = LucideIcons.rows3;
  static const IconData columns = LucideIcons.columns3;
  static const IconData skipBack = LucideIcons.skipBack;
  static const IconData skipForward = LucideIcons.skipForward;
  static const IconData zoomIn = LucideIcons.zoomIn;
  static const IconData maximize = LucideIcons.maximize;
  static const IconData settings2 = LucideIcons.settings2;
  static const IconData mail = LucideIcons.mail;
  static const IconData lock = LucideIcons.lock;
  static const IconData keyRound = LucideIcons.keyRound;
  static const IconData eyeOff = LucideIcons.eyeOff;
  static const IconData shieldCheck = LucideIcons.shieldCheck;
  static const IconData badgeCheck = LucideIcons.badgeCheck;
  static const IconData badgeCheckFilled = Icons.verified_rounded;
  static const IconData circleDotDashed = LucideIcons.circleDotDashed;
  static const IconData wifi = LucideIcons.wifi;

  // Ikon tema
  static const IconData lightMode = LucideIcons.sun;
  static const IconData darkMode = LucideIcons.moon;
}
