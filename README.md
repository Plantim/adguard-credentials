# change_credentials.ps1

Script autonome pour modifier l'identifiant et/ou le mot de passe d'AdGuardHome sous Windows.


### 🖥️ Menu du script (Interface Console)

Lorsque vous exécutez le script, une interface textuelle interactive s'affiche directement dans votre console PowerShell :

```text
==========================================
    AdGuardHome Credentials Tool
==========================================

  [1] Change Username/Password in YAML
  [2] Generate BCrypt hash from password
  [3] Exit

==========================================
Select an option (1-3):
```

---

## Utilisations

Avec prompt interactif
```powershell
.\change_credentials.ps1
```

Directement l'option 1 avec le chemin du YAML
```powershell
.\change_credentials.ps1 -ConfigPath "C:\AdGuardHome\AdGuardHome.yaml"
```

## Fonctionnement

1. S'élève automatiquement en administrateur (UAC) — nécessaire pour écrire le YAML et redémarrer le service
2. Génère le hash BCrypt via le package NuGet `BCrypt.Net-Next 4.2.0` (chargé en mémoire, aucune installation)
3. Remplace la section `users:` dans le fichier YAML
4. Redémarre AdGuardHome (`AdGuardHome.exe -s restart`)

## Dépendances

- PowerShell 5.1+
- .NET Framework 4.7.2+ (présent par défaut sur Windows 10/11)
- Connexion Internet (pour télécharger BCrypt.Net-Next via NuGet)
