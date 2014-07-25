.. role:: raw-html(raw)
   :format: html

.. role:: raw-latex(raw)
   :format: latex


.. _�quipement communicant:
.. _�quipements communicants:


Mod�lisation des �quipements communicants (``CommunicatingDevice``)
===================================================================


Pr�sentation
------------

Ce mod�le d�crit tout type d'�quipements capables de communiquer, en �mission et/ou r�ception, via des `liens de communication`_.

Ces �quipements sont appel�s en g�n�ral � faire partie d'un `r�seau de communication`_.


Mod�lisation
------------


+-----------------------------+-----------------------------------+---------------------+---------------------+
| Nom de l'attribut           | Signification                     | Unit�s              | Valeurs typiques    |
+=============================+===================================+=====================+=====================+
| ``emitting_power``          | Puissance d'�mission              | dB                  | 0..90dB             |
+-----------------------------+-----------------------------------+---------------------+---------------------+
| ``receiver_sensibility``    | Sensibilit� de r�ception          | dB                  | 0..90dB             |
+-----------------------------+-----------------------------------+---------------------+---------------------+


Impl�mentation
--------------

La classe correspondante est impl�ment�e dans class_CommunicatingDevice.erl_.
