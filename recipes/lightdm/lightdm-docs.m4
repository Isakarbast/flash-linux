dnl Stand-ins for the gtk-doc and yelp-tools macros: Flash Linux builds
dnl LightDM without its API reference and help pages.
AC_DEFUN([GTK_DOC_CHECK], [AM_CONDITIONAL([ENABLE_GTK_DOC], [false])])
AC_DEFUN([YELP_HELP_INIT], [])
