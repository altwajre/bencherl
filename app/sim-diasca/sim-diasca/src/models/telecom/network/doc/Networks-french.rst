.. role:: raw-html(raw)
   :format: html

.. role:: raw-latex(raw)
   :format: latex


.. _r�seau de communication:
.. _r�seaux de communication:



Mod�lisation g�n�rique de r�seaux t�l�com (``Network``)
=======================================================


.. contents:: Table des mati�res
	:local:


Pr�sentation
------------

Un r�seau t�l�com g�n�rique (ind�pendamment de la nature de ses communications) est ici mod�lis� sous la forme d'un graphe dirig� potentiellement cyclique, dont :

  - les sommets sont les �quipements communicants en �tat de communiquer
  - les ar�tes repr�sentent le fait que deux �quipements peuvent communiquer directement (sans interm�diaire)

Ce graphe peut lui-m�me �tre le produit de l'�valuation d'un graphe plus complet, qui mod�lise :

  - la puissance d'�mission des �quipements et leur sensibilit� de r�ception
  - la longueur et l'att�nuation lin�ique des liens de communication les liant

Plus pr�cis�ment, dans un tel r�seau, trois types d'�l�ments de plus haut niveau sont d�finis :

 - le type *interconnexion* (``Interconnection``)

 - le type *lien* (``DataLink``)

 - le type *�quipement communicant* (``class NetworkDevice``)



Avancement
----------

Le mod�le de communication mis en place pour le CPL pr�figure le mod�le de r�seau complet, qui pourrait �tre en place � l'occasion du d�veloppement du mod�le avanc� fond� sur les calculs d'att�nuation du signal.
