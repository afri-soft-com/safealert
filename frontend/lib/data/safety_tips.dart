import 'package:flutter/material.dart';
import '../theme.dart';

class SafetyCategory {
  final String icon;
  final String title;
  final Color color;
  final List<String> tips;
  const SafetyCategory(this.icon, this.title, this.color, this.tips);
}

const safetyCategories = [
  SafetyCategory('🚶', 'Déplacements', AppColors.bleu, [
    'Évitez de marcher seul(e) la nuit dans les zones non éclairées.',
    'Prévenez un proche de votre trajet et de l\'heure estimée d\'arrivée.',
    'Utilisez les transports officiels ou les taxis recommandés.',
    'Gardez votre téléphone chargé et visible seulement en cas de besoin.',
    'Restez sur les axes principaux et évitez les raccourcis isolés.',
  ]),
  SafetyCategory('📱', 'Téléphone & numérique', AppColors.orange, [
    'Mémorisez les numéros d\'urgence (112 police, 15 hôpital, 118 pompiers).',
    'Activez le partage de position avec vos contacts de confiance.',
    'Configurez le mode discret SafeAlert (Volume↓ 3×) pour les situations dangereuses.',
    'Ne partagez pas votre position en temps réel sur les réseaux sociaux.',
    'Sauvegardez les numéros d\'urgence dans votre répertoire hors-ligne.',
  ]),
  SafetyCategory('🏠', 'Domicile', AppColors.vert, [
    'Verrouillez toujours vos portes et fenêtres, même en journée.',
    'Connaissez vos voisins et échangez vos numéros d\'urgence.',
    'Installez un éclairage extérieur automatique si possible.',
    'Ne faites pas entrer d\'inconnus sans vérifier leur identité.',
    'Identifiez les issues de secours et les cachettes dans votre logement.',
  ]),
  SafetyCategory('👥', 'Communauté', AppColors.rouge, [
    'Créez un groupe de voisins SafeAlert pour vous alerter mutuellement.',
    'Participez aux réunions de quartier et aux comités de sécurité locaux.',
    'Signalez tout comportement suspect via l\'application (anonymement si nécessaire).',
    'Encouragez vos voisins à rejoindre le cercle de confiance.',
    'Connaissez le chef de quartier et les agents de sécurité locaux.',
  ]),
  SafetyCategory('🚨', 'Urgence', AppColors.rougeDark, [
    'En cas d\'agression : ne résistez pas, donnez ce qui est demandé.',
    'Utilisez le bouton SOS discret (Volume↓ 3×) silencieusement.',
    'Après une agression, mettez-vous en sécurité puis signalez via l\'app.',
    'Notez les détails : taille, vêtements, direction de fuite, véhicule.',
    'Consultez un médecin même en l\'absence de blessures visibles.',
  ]),
  SafetyCategory('👧', 'Enfants & familles', AppColors.bleuFonce, [
    'Apprenez à vos enfants votre numéro de téléphone et l\'adresse.',
    'Identifiez un voisin de confiance chez qui les enfants peuvent se réfugier.',
    'Établissez un mot de passe familial pour les situations d\'urgence.',
    'Ne laissez pas les enfants jouer seuls dans des zones non surveillées.',
    'Inscrivez les enfants à un programme de sécurité communautaire.',
  ]),
];