# Tombstone flash 8

Boot ini menghasilkan **62 berkas** (31 tombstone + 31 `.pb`) -- yang pertama
kali muncul sejak tambalan `O_TMPFILE` pada `tombstoned`. Sebelumnya perangkat
ini tidak pernah bisa menulis satu pun.

Ke-31 tombstone menunjuk crash yang sama persis, hanya berbeda pid dan alamat:

    pid ... name: main  >>> zygote <<<
    signal 6 (SIGABRT)
    Abort message: 'JNI FatalError called: (system_server)
      frameworks/base/core/jni/com_android_internal_os_Zygote.cpp:1991:
      createProcessGroup(1000, 0) failed: No such file or directory'

Yang disimpan di sini hanya satu pasang sebagai wakil. Tiga puluh salinan
lainnya tidak menambah informasi apa pun dan berukuran 18 MB.
