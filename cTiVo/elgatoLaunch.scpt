FasdUAS 1.101.10   ��   ��    k             l     ��  ��     !/usr/bin/osascript     � 	 	 & ! / u s r / b i n / o s a s c r i p t   
  
 l     ��  ��    9 3Applescript to link cTivo to ElGato Turbo sw and hw     �   f A p p l e s c r i p t   t o   l i n k   c T i v o   t o   E l G a t o   T u r b o   s w   a n d   h w      l     ��������  ��  ��        l     ��  ��    , &  Written by Hugh Mackworth on 1/31/13     �   L     W r i t t e n   b y   H u g h   M a c k w o r t h   o n   1 / 3 1 / 1 3      l     ��  ��    , &  Copyright 2013. All rights reserved.     �   L     C o p y r i g h t   2 0 1 3 .   A l l   r i g h t s   r e s e r v e d .      l     ��������  ��  ��        i          I      �� !���� 0 removequotes removeQuotes !  "�� " o      ���� 0 mytext myText��  ��     Z      # $�� % # =      & ' & n      ( ) ( 4   �� *
�� 
cha  * m    ����  ) o     ���� 0 mytext myText ' m     + + � , ,  " $ l  	  - . / - L   	  0 0 n   	  1 2 1 7  
 �� 3 4
�� 
cha  3 m    ����  4 m    ������ 2 o   	 
���� 0 mytext myText .  delete quotes    / � 5 5  d e l e t e   q u o t e s��   % L     6 6 o    ���� 0 mytext myText   7 8 7 l     ��������  ��  ��   8  9�� 9 i     : ; : I     �� <��
�� .aevtoappnull  �   � **** < o      ���� 0 argv  ��   ; k    Q = =  > ? > Q      @ A B @ k     C C  D E D O    F G F r     H I H n     J K J 1    ��
�� 
pnam K 5    �� L��
�� 
appf L m   	 
 M M � N N   c o m . e l g a t o . T u r b o
�� kfrmID   I o      ���� 0 turboappname turboAppName G m     O O�                                                                                  MACS  alis    t  Macintosh HD               �0��H+     2
Finder.app                                                      �c�k"        ����  	                CoreServices    �1�      �͒       2   ,   +  6Macintosh HD:System: Library: CoreServices: Finder.app   
 F i n d e r . a p p    M a c i n t o s h   H D  &System/Library/CoreServices/Finder.app  / ��   E  P�� P l   ��������  ��  ��  ��   A R      ������
�� .ascrerr ****      � ****��  ��   B l    Q R S Q =     T U T o    ���� 0 turboappname turboAppName U m     V V � W W  N o t   F o u n d R  "Turbo.264 HD.app"    S � X X $ " T u r b o . 2 6 4   H D . a p p " ?  Y Z Y Z   N [ \���� [ H    # ] ] =    " ^ _ ^ o     ���� 0 turboappname turboAppName _ m     ! ` ` � a a  N o t   F o u n d \ k   &J b b  c d c Q   & J e f g e n   ) . h i h 4   * -�� j
�� 
cobj j m   + ,����  i o   ) *���� 0 argv   f R      ������
�� .ascrerr ****      � ****��  ��   g k   6 J k k  l m l I  6 ;�� n��
�� .ascrcmnt****      � **** n m   6 7 o o � p p ( R u n n i n g   i n   t e s t   m o d e��   m  q r q l  < <�� s t��   s � �set argv to {"HD720p", "-edl", "/tmp/cTivo/The Tonight Show With Jay Leno.m4v", "-o", "~/Movies/TiVoShows/The Tonight Show With Jay Leno.m4v", "-i", "~/Movies/TiVoShows/The Tonight Show With Jay Leno.mp4"}    t � u u� s e t   a r g v   t o   { " H D 7 2 0 p " ,   " - e d l " ,   " / t m p / c T i v o / T h e   T o n i g h t   S h o w   W i t h   J a y   L e n o . m 4 v " ,   " - o " ,   " ~ / M o v i e s / T i V o S h o w s / T h e   T o n i g h t   S h o w   W i t h   J a y   L e n o . m 4 v " ,   " - i " ,   " ~ / M o v i e s / T i V o S h o w s / T h e   T o n i g h t   S h o w   W i t h   J a y   L e n o . m p 4 " } r  v w v r   < H x y x J   < F z z  { | { m   < = } } � ~ ~  H D 1 0 8 0 p |   �  m   = > � � � � �  - i �  � � � m   > ? � � � � � � / t m p / c t i v o / b u f f e r I t ' s   A l w a y s   S u n n y   i n   P h i l a d e l p h i a -   C h a r d e e   M a c D e n n i s -   T h e   G a m e   o f   G a m e s 7 . m p g �  ��� � m   ? B � � � � � � / U s e r s / h u g h / M o v i e s / T i v o S h o w s / I t ' s   A l w a y s   S u n n y   i n   P h i l a d e l p h i a -   C h a r d e e   M a c D e n n i s -   T h e   G a m e   o f   G a m e s - 6 . m p 4��   y o      ���� 0 argv   w  ��� � l  I I��������  ��  ��  ��   d  � � � Q   Kx � � � � P   Nk ��� � � k   Uj � �  � � � r   U b � � � I   U ^�� ����� 0 removequotes removeQuotes �  ��� � n   V Z � � � 4  W Z�� �
�� 
cobj � m   X Y����  � o   V W���� 0 argv  ��  ��   � o      ���� 0 
formattype 
formatType �  � � � r   c j � � � n   c h � � � 1   d h��
�� 
rest � o   c d���� 0 argv   � o      ���� 0 argv   �  � � � l  k k��������  ��  ��   �  � � � l  k k�� � ���   � ( "Video options = Elgato format name    � � � � D V i d e o   o p t i o n s   =   E l g a t o   f o r m a t   n a m e �  � � � Z   k � � ��� � � =   k r � � � o   k n���� 0 
formattype 
formatType � m   n q � � � � �  c u s t o m � k   u � � �  � � � l  u � � � � � r   u � � � � I   u ~�� ����� 0 removequotes removeQuotes �  ��� � n   v z � � � 4  w z�� �
�� 
cobj � m   x y����  � o   v w���� 0 argv  ��  ��   � o      ���� 0 customformat customFormat �  real format Name    � � � �   r e a l   f o r m a t   N a m e �  ��� � r   � � � � � n   � � � � � 1   � ���
�� 
rest � o   � ����� 0 argv   � o      ���� 0 argv  ��  ��   � r   � � � � � m   � � � � � � � 
 W R O N G � o      ���� 0 customformat customFormat �  � � � Z   � � � ��� � � =   � � � � � n   � � � � � 4  � ��� �
�� 
cobj � m   � �����  � o   � ����� 0 argv   � m   � � � � � � �  - e d l � k   � � � �  � � � r   � � � � � n   � � � � � 1   � ���
�� 
rest � o   � ����� 0 argv   � o      ���� 0 argv   �  � � � r   � � � � � n   � � � � � 4  � ��� �
�� 
cobj � m   � �����  � o   � ����� 0 argv   � o      ���� 0 edlfile EDLFile �  ��� � r   � � � � � n   � � � � � 1   � ���
�� 
rest � o   � ����� 0 argv   � o      ���� 0 argv  ��  ��   � r   � � � � � m   � � � � � � �   � o      ���� 0 edlfile EDLFile �  � � � l  � ���������  ��  ��   �  � � � r   � � � � � m   � ���
�� boovfals � o      ���� 0 gotdestfile gotDestFile �  � � � r   � � � � � I   � ��� ����� 0 removequotes removeQuotes �  ��� � n   � � � � � 4  � ��� �
�� 
cobj � m   � �����  � o   � ����� 0 argv  ��  ��   � o      ���� 0 nextitem nextItem �  � � � Z   � � ����� � G   � � �  � =   � � o   � ����� 0 nextitem nextItem m   � � �  - o  =   � � o   � ����� 0 nextitem nextItem m   � � �  - - o u t p u t � k   �		 

 r   � � n   � � 1   � ���
�� 
rest o   � ����� 0 argv   o      ���� 0 argv    r   � � n   � � 4  � ���
�� 
cobj m   � �����  o   � ����� 0 argv   o      �� 0 destfile    r    n    1  �~
�~ 
rest o   �}�} 0 argv   o      �|�| 0 argv    r    m  	�{
�{ boovtrue  o      �z�z 0 gotdestfile gotDestFile !�y! r  "#" I  �x$�w�x 0 removequotes removeQuotes$ %�v% n  &'& 4 �u(
�u 
cobj( m  �t�t ' o  �s�s 0 argv  �v  �w  # o      �r�r 0 nextitem nextItem�y  ��  ��   � )*) l   �q�p�o�q  �p  �o  * +,+ Z   C-.�n�m- G   5/0/ =   '121 o   #�l�l 0 nextitem nextItem2 m  #&33 �44  - i0 =  *1565 o  *-�k�k 0 nextitem nextItem6 m  -077 �88  - - i n p u t. r  8?9:9 n  8=;<; 1  9=�j
�j 
rest< o  89�i�i 0 argv  : o      �h�h 0 argv  �n  �m  , =>= l DL?@A? r  DLBCB n  DHDED 4 EH�gF
�g 
cobjF m  FG�f�f E o  DE�e�e 0 argv  C o      �d�d 0 
sourcefile  @ !  ok to skip input file flag   A �GG 6   o k   t o   s k i p   i n p u t   f i l e   f l a g> HIH r  MTJKJ n  MRLML 1  NR�c
�c 
restM o  MN�b�b 0 argv  K o      �a�a 0 argv  I NON l UU�`�_�^�`  �_  �^  O PQP Z  UhRS�]�\R H  UYTT o  UX�[�[ 0 gotdestfile gotDestFileS r  \dUVU n  \`WXW 4 ]`�ZY
�Z 
cobjY m  ^_�Y�Y X o  \]�X�X 0 argv  V o      �W�W 0 destfile  �]  �\  Q Z�VZ l ii�U�T�S�U  �T  �S  �V  ��   � �R�Q
�R conscase�Q   � R      �P[�O
�P .ascrerr ****      � ****[ o      �N�N 0 errormsg errorMsg�O   � I sx�M\�L
�M .ascrcmnt****      � ****\ o  st�K�K 0 errormsg errorMsg�L   � ]^] I y��J_�I
�J .ascrcmnt****      � ****_ b  y�`a` b  y�bcb b  y�ded b  y�fgf b  y�hih b  y�jkj b  y�lml b  y�non m  y|pp �qq  f r o m :  o o  |�H�H 0 
sourcefile  m m  ��rr �ss 
   t o :  k o  ���G�G 0 destfile  i m  ��tt �uu    f o r m a t :  g o  ���F�F 0 
formattype 
formatTypee m  ��vv �ww    w i t h   e d l :  c o  ���E�E 0 edlfile EDLFilea m  ��xx �yy  
 	 	 	�I  ^ z{z l ���D|}�D  |   		if not EDLFile = "" then   } �~~ 4 	 	 i f   n o t   E D L F i l e   =   " "   t h e n{ � l ���C���C  � A ;			set newEDLFileName to text 1 thru -4 of destfile & "edl"   � ��� v 	 	 	 s e t   n e w E D L F i l e N a m e   t o   t e x t   1   t h r u   - 4   o f   d e s t f i l e   &   " e d l "� ��� l ���B���B  � ] W			set mvCmd to "mv -f " & quoted form of EDLFile & " " & quoted form of newEDLFileName   � ��� � 	 	 	 s e t   m v C m d   t o   " m v   - f   "   &   q u o t e d   f o r m   o f   E D L F i l e   &   "   "   &   q u o t e d   f o r m   o f   n e w E D L F i l e N a m e� ��� l ���A���A  �  			try   � ���  	 	 	 t r y� ��� l ���@���@  � / )				set shellOut to do shell script mvCmd   � ��� R 	 	 	 	 s e t   s h e l l O u t   t o   d o   s h e l l   s c r i p t   m v C m d� ��� l ���?���?  �  
			end try   � ���  	 	 	 e n d   t r y� ��� l ���>���>  �  		end if   � ���  	 	 e n d   i f� ��� l ���=�<�;�=  �<  �;  � ��:� w  �J��� Z  �J���9�8� H  ���� =  ����� o  ���7�7 0 turboappname turboAppName� m  ���� ���  � k  �F�� ��� I ���6��5
�6 .ascrcmnt****      � ****� m  ���� ���  T u r b o   A�5  � ��� r  ����� m  ���4�4  � o      �3�3 0 counter  � ��� V  ���� k  ���� ��� I ���2��1
�2 .sysodelanull��� ��� nmbr� m  ���0�0 �1  � ��� r  ����� [  ����� o  ���/�/ 0 counter  � m  ���.�. � o      �-�- 0 counter  � ��� I ���,��+
�, .ascrcmnt****      � ****� c  ����� b  ����� m  ���� ���  B� o  ���*�* 0 counter  � m  ���)
�) 
ctxt�+  � ��(� Z  �����'�&� ?  ����� o  ���%�% 0 counter  � m  ���$�$ � l ������ L  ���� m  ���#�# � . (required to report back every 60 seconds   � ��� P r e q u i r e d   t o   r e p o r t   b a c k   e v e r y   6 0   s e c o n d s�'  �&  �(  � = ����� n  ����� 1  ���"
�" 
prun� 4  ���!�
�! 
capp� o  ��� �  0 turboappname turboAppName� m  ���
� boovtrue� ��� O  F��� Q  E���� k  �� ��� I ���
� .ascrcmnt****      � ****� m  �� ���  C�  � ��� I ���
� .ascrnoop****      � ****�  �  � ��� l "���� I "���
� .sysodelanull��� ��� nmbr� m  �� �  �  let it setup   � ���  l e t   i t   s e t u p� ��� l ##����  � _ YiPod High/iPod Standard/Sony PSP/ AppleTV/iPhone/YouTube/YouTubeHD/HD720p/ HD1080p/custom   � ��� � i P o d   H i g h / i P o d   S t a n d a r d / S o n y   P S P /   A p p l e T V / i P h o n e / Y o u T u b e / Y o u T u b e H D / H D 7 2 0 p /   H D 1 0 8 0 p / c u s t o m� ��� I #*���
� .ascrcmnt****      � ****� m  #&�� ���  D�  � ��� P  +���� k  2�� ��� Z  2��� � l 29�� =  29 o  25�� 0 
formattype 
formatType m  58 �  i P o d H i g h�  �  � I <W�
� .TuBoAddfnull���     file o  <?�� 0 
sourcefile   �	

� 
Etgt	 o  BE�
�
 0 destfile  
 �	
�	 
Etyp m  HK�
� EtypIpdB ��
� 
Repl m  NQ�
� savoyes �     l Zo�� G  Zo =  Za o  Z]�� 0 
formattype 
formatType m  ]` �  i p o d S t a n d a r d =  dk o  dg�� 0 
formattype 
formatType m  gj �  i p o d�  �    I r�� 
�  .TuBoAddfnull���     file o  ru���� 0 
sourcefile   �� 
�� 
Etgt o  x{���� 0 destfile    ��!"
�� 
Etyp! m  ~���
�� EtypIpdS" ��#��
�� 
Repl# m  ����
�� savoyes ��   $%$ l ��&����& G  ��'(' =  ��)*) o  ������ 0 
formattype 
formatType* m  ��++ �,,  S o n y p s p( =  ��-.- o  ������ 0 
formattype 
formatType. m  ��// �00  p s p��  ��  % 121 I ����34
�� .TuBoAddfnull���     file3 o  ������ 0 
sourcefile  4 ��56
�� 
Etgt5 o  ������ 0 destfile  6 ��78
�� 
Etyp7 m  ����
�� EtypPspH8 ��9��
�� 
Repl9 m  ����
�� savoyes ��  2 :;: l ��<����< =  ��=>= o  ������ 0 
formattype 
formatType> m  ��?? �@@  a p p l e T V��  ��  ; ABA I ����CD
�� .TuBoAddfnull���     fileC o  ������ 0 
sourcefile  D ��EF
�� 
EtgtE o  ������ 0 destfile  F ��GH
�� 
EtypG m  ����
�� EtypApTVH ��I��
�� 
ReplI m  ����
�� savoyes ��  B JKJ l ��L����L =  ��MNM o  ������ 0 
formattype 
formatTypeN m  ��OO �PP  i P h o n e��  ��  K QRQ I ���ST
�� .TuBoAddfnull���     fileS o  ������ 0 
sourcefile  T ��UV
�� 
EtgtU o  ����� 0 destfile  V ��WX
�� 
EtypW m  ��
�� EtypiPhnX ��Y��
�� 
ReplY m  
��
�� savoyes ��  R Z[Z l \����\ =  ]^] o  ���� 0 
formattype 
formatType^ m  __ �``  Y o u T u b e��  ��  [ aba I  ;��cd
�� .TuBoAddfnull���     filec o   #���� 0 
sourcefile  d ��ef
�� 
Etgte o  &)���� 0 destfile  f ��gh
�� 
Etypg m  ,/��
�� EtypYouTh ��i��
�� 
Repli m  25��
�� savoyes ��  b jkj l >El����l =  >Emnm o  >A���� 0 
formattype 
formatTypen m  ADoo �pp  Y o u T u b e H D��  ��  k qrq I Hc��st
�� .TuBoAddfnull���     files o  HK���� 0 
sourcefile  t ��uv
�� 
Etgtu o  NQ���� 0 destfile  v ��wx
�� 
Etypw m  TW��
�� EtypYoHDx ��y��
�� 
Reply m  Z]��
�� savoyes ��  r z{z l fm|����| =  fm}~} o  fi���� 0 
formattype 
formatType~ m  il ���  H D 7 2 0 p��  ��  { ��� I p�����
�� .TuBoAddfnull���     file� o  ps���� 0 
sourcefile  � ����
�� 
Etgt� o  vy���� 0 destfile  � ����
�� 
Etyp� m  |��
�� EtypH720� �����
�� 
Repl� m  ����
�� savoyes ��  � ��� l �������� =  ����� o  ������ 0 
formattype 
formatType� m  ���� ���  H D 1 0 8 0 p��  ��  � ��� I ������
�� .TuBoAddfnull���     file� o  ������ 0 
sourcefile  � ����
�� 
Etgt� o  ������ 0 destfile  � ����
�� 
Etyp� m  ����
�� EtypH180� �����
�� 
Repl� m  ����
�� savoyes ��  � ��� l �������� =  ����� o  ������ 0 
formattype 
formatType� m  ���� ���  c u s t o m��  ��  � ���� I ������
�� .TuBoAddfnull���     file� o  ������ 0 
sourcefile  � ����
�� 
Etgt� o  ������ 0 destfile  � ����
�� 
Etyp� m  ����
�� EtypCust� ����
�� 
CusN� o  ������ 0 customformat customFormat� �����
�� 
Repl� m  ����
�� savoyes ��  ��   I ������
�� .TuBoAddfnull���     file� o  ������ 0 
sourcefile  � ����
�� 
Etgt� o  ������ 0 destfile  � �����
�� 
Repl� m  ����
�� boovtrue��  � ��� I ������
�� .TuBoTencnull��� ��� null��  � �����
�� 
NoEr� m  ����
�� boovtrue��  � ��� l ���� I �����
�� .sysodelanull��� ��� nmbr� m  ���� ��  �  wait for it to start   � ��� ( w a i t   f o r   i t   t o   s t a r t� ���� I �����
�� .ascrcmnt****      � ****� m  �� ���  E��  ��  �  � ����
�� conscase��  �  � R      ���~
� .ascrerr ****      � ****� o      �}�} 0 errormsg errorMsg�~  � k  E�� ��� I !�|��{
�| .ascrcmnt****      � ****� b  ��� m  �� ���  N o   l a u n c h :  � o  �z�z 0 errormsg errorMsg�{  � ��y� Q  "E���� O %4��� I .3�x�w�v
�x .aevtquitnull��� ��� null�w  �v  � 4  %+�u�
�u 
capp� o  )*�t�t 0 turboappname turboAppName� R      �s��r
�s .ascrerr ****      � ****� o      �q�q 0 quiterrormsg quitErrorMsg�r  � I <E�p��o
�p .ascrcmnt****      � ****� b  <A��� m  <?�� ���  Q u i t   f a i l e d� o  ?@�n�n 0 quiterrormsg quitErrorMsg�o  �y  � 4  	�m�
�m 
capp� o  �l�l 0 turboappname turboAppName�  �9  �8  ��                                                                                  TuRB  alis    |  Macintosh HD               �0��H+   �eTurbo.264 HD.app                                                �:��R�        ����  	                	VideoApps     �1�      �R�     �e   O  6Macintosh HD:Applications: VideoApps: Turbo.264 HD.app  "  T u r b o . 2 6 4   H D . a p p    M a c i n t o s h   H D  'Applications/VideoApps/Turbo.264 HD.app   / ��  �:  ��  ��   Z ��� l OO�k�j�i�k  �j  �i  � ��h� L  OQ�� o  OP�g�g 0 turboappname turboAppName�h  ��       �f����� � ��e����d�c�b�a�`�_�f  � �^�]�\�[�Z�Y�X�W�V�U�T�S�R�Q�P�O�^ 0 removequotes removeQuotes
�] .aevtoappnull  �   � ****�\ 0 turboappname turboAppName�[ 0 
formattype 
formatType�Z 0 customformat customFormat�Y 0 edlfile EDLFile�X 0 gotdestfile gotDestFile�W 0 nextitem nextItem�V 0 
sourcefile  �U 0 destfile  �T 0 counter  �S  �R  �Q  �P  �O  � �N  �M�L���K�N 0 removequotes removeQuotes�M �J��J �  �I�I 0 mytext myText�L  � �H�H 0 mytext myText� �G +�F
�G 
cha �F���K ��k/�  �[�\[Zl\Z�2EY �� �E ;�D�C���B
�E .aevtoappnull  �   � ****�D 0 argv  �C  � �A�@�?�A 0 argv  �@ 0 errormsg errorMsg�? 0 quiterrormsg quitErrorMsg� ] O�> M�=�<�;�:�9 V `�8 o�7 } � � ��6 ��5�4�3 ��2 � ��1 ��0�/�.�-37�,�+prtvx����*�)�(�'��&�%��$��#�"�!� ����+/�?�O�_�o���������������
�> 
appf
�= kfrmID  
�< 
pnam�; 0 turboappname turboAppName�:  �9  
�8 
cobj
�7 .ascrcmnt****      � ****�6 �5 0 removequotes removeQuotes�4 0 
formattype 
formatType
�3 
rest�2 0 customformat customFormat�1 0 edlfile EDLFile�0 0 gotdestfile gotDestFile�/ 0 nextitem nextItem
�. 
bool�- 0 destfile  �, 0 
sourcefile  �+ 0 errormsg errorMsg�* 0 counter  
�) 
capp
�( 
prun
�' .sysodelanull��� ��� nmbr
�& 
ctxt�% 
�$ .ascrnoop****      � ****
�# 
Etgt
�" 
Etyp
�! EtypIpdB
�  
Repl
� savoyes � 
� .TuBoAddfnull���     file
� EtypIpdS
� EtypPspH
� EtypApTV
� EtypiPhn
� EtypYouT
� EtypYoHD
� EtypH720
� EtypH180
� EtypCust
� 
CusN� 
� 
NoEr
� .TuBoTencnull��� ��� null
� .aevtquitnull��� ��� null� 0 quiterrormsg quitErrorMsg�BR � *���0�,E�UOPW 
X  �� O�� ) 
��m/EW X  �j O���a a vE�OPO"ga *��k/k+ E` O�a ,E�O_ a   *��k/k+ E` O�a ,E�Y 	a E` O��k/a   �a ,E�O��k/E` O�a ,E�Y 	a E` OfE` O*��k/k+ E` O_ a  
 _ a  a  & 1�a ,E�O��k/E` !O�a ,E�OeE` O*��k/k+ E` Y hO_ a " 
 _ a # a  & �a ,E�Y hO��k/E` $O�a ,E�O_  ��k/E` !Y hOPVW X % �j Oa &_ $%a '%_ !%a (%_ %a )%_ %a *%j Oa +Z�a , �a -j OjE` .O Eh*a /�/a 0,e lj 1O_ .kE` .Oa 2_ .%a 3&j O_ .a 4 kY h[OY��O*a /�/;a 5j O*j 6Olj 1Oa 7j Oga �_ a 8   _ $a 9_ !a :a ;a <a =a > ?Y�_ a @ 
 _ a A a  &  _ $a 9_ !a :a Ba <a =a > ?Yi_ a C 
 _ a D a  &  _ $a 9_ !a :a Ea <a =a > ?Y3_ a F   _ $a 9_ !a :a Ga <a =a > ?Y_ a H   _ $a 9_ !a :a Ia <a =a > ?Y �_ a J   _ $a 9_ !a :a Ka <a =a > ?Y �_ a L   _ $a 9_ !a :a Ma <a =a > ?Y �_ a N   _ $a 9_ !a :a Oa <a =a > ?Y k_ a P   _ $a 9_ !a :a Qa <a =a > ?Y C_ a R  &_ $a 9_ !a :a Sa T_ a <a =a U ?Y _ $a 9_ !a <ea  ?O*a Vel WOlj 1Oa Xj VW 4X % a Y�%j O *a /�/ *j ZUW X [ a \�%j UY hY hO�� ���   T u r b o . 2 6 4   H D . a p p� ���  A p p l e T V
�e boovfals� ���  - i� ��� & / t m p / c t i v o / t e s t . m p g� ���  t e s t . m p 4�d  �c  �b  �a  �`  �_  ascr  ��ޭ