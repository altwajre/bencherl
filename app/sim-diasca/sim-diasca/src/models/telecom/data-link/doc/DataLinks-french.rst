.. _lien t�l�com:
.. _liens t�l�com:

.. _lien de communication:
.. _liens de communication:


Mod�lisation des liens de communication (``DataLink``)
======================================================


Pr�sentation
------------

En terme de liens de communication, de nombreuses variations sont possibles :

  - connexion permanente ou non

  - monodirectionnelle ou bidirectionnelle (altern�e *half-duplex* ou simultan�e *full-duplex*)

  - facteur d'att�nuation (en d�cibel par m�tre)

  - longueur

  - tarification

  - bande-passante maximale effective (d�bit-cr�te)

  - latence (dur�e de transit d'une donn�e isol�e)

  - mod�le de bruits (interf�rence)

  - gestion de la congestion

  - caract�re synchrone (fond� sur une horloge) ou asynchrone


Mod�lisation
------------

+-----------------------------+-----------------------------------+---------------------+---------------------+
| Nom de l'attribut           | Signification                     | Unit�s              | Valeurs typiques    |
+=============================+===================================+=====================+=====================+
| ``attenuation_coefficient`` | Att�nuation lin�ique du signal    | dB/m                | 0..90dB             |
+-----------------------------+-----------------------------------+---------------------+---------------------+
| ``length``                  | Longueur du lien                  | m                   | 0.1m..20km          |
+-----------------------------+-----------------------------------+---------------------+---------------------+
| ``data_type``               | Type des informations v�hicul�es, | N/A                 | ``numerical``,      |
|                             | num�riques ou analogiques         |                     | ``analogical``      |
+-----------------------------+-----------------------------------+---------------------+---------------------+



Att�nuation
...........


Il s'agit de la perte de puissance du signal en d�cibels (dB) qui est fonction de la distance entre les interlocuteurs et de la qualit� du lien, et qui est consid�r�e ici comme exponentielle [#]_.

Chaque lien est suppos� d�crit par une att�nuation lin�ique (``attenuation_factor``), caract�ristique de ce lien. Par exemple, pour une communication filaire, ce facteur est fonction de la section du c�ble, de son mat�riau, de sa forme, de la fr�quence des signaux, etc [#]_.

.. [#] Source : article de Wikipedia sur l'`att�nuation <http://en.wikipedia.org/wiki/Attenuation>`_


Cette att�nuation lin�ique est suppos�e constante (lien homog�ne), si bien que l'att�nuation effective du lien est �gale � ``A = attenuation_factor * length``, avec ``length`` : longueur de ce lien.

.. [#] Voir aussi : article de Wikipedia sur les `coefficient d'att�nuation <http://en.wikipedia.org/wiki/Attenuation_coefficient#Linear_Attenuation_Coefficient>`_, notamment lin�iques.


Il est alors possible de mod�liser un r�seau complet � partir d'un nombre quelconque de ces liens t�l�com, agenc�s selon une topologie donn�e, pour �valuer le bilan de liaison [#]_.

.. [#] Le bilan de liaison est un calcul par �tapes permettant de d�terminer la qualit� d'une liaison. Les d�tails varient selon la nature du m�dia, hertzien, ligne, fibre optique, et le type de signaux et de modulation, mais le principe est le m�me. C'est le calcul global qui relie tous les domaines : radio�lectricit�, traitement du signal, protocoles, etc. Source : article de Wikipedia `du m�me nom <http://fr.wikipedia.org/wiki/Bilan_de_liaison>`_.



Diaphonie
.........

Elle n'est pas mod�lis�e actuellement. Il serait envisageable n�anmoins de la prendre en compte en ouvrant la possibilit� de d�finir un couplage potentiel entre plusieurs liaisons, a minima via un coefficient quantifiant la proportion, en puissance, de signal transitant d'un lien � l'autre.


Impl�mentation
--------------

Elle r�side principalement dans class_DataLink.hrl_ et class_DataLink.erl_. Seule une impl�mentation minimaliste existe, elle sera d�velopp�e plus pr�cis�ment en fonction des liens - notamment WAN - qui seront � simuler.
