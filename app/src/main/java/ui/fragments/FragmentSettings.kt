/*
    Copyright (C) 2016 sandstranger
    Copyright (C) 2018, 2019 Ilya Zhuravlev

    This file is part of OpenMW-Android.

    OpenMW-Android is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    OpenMW-Android is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with OpenMW-Android.  If not, see <https://www.gnu.org/licenses/>.
*/

package ui.fragments

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.DialogInterface
import android.content.Intent
import android.content.SharedPreferences
import android.content.SharedPreferences.OnSharedPreferenceChangeListener
import android.content.pm.PackageManager
import android.os.Bundle
import android.preference.EditTextPreference
import android.preference.Preference
import android.preference.PreferenceFragment
import android.preference.PreferenceGroup
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.libopenmw.openmw.R
import file.GameInstaller
import ui.activity.ConfigureControls
import ui.activity.MainActivity
import ui.activity.ModsActivity
import ui.activity.SettingsActivity
import java.io.File
import utils.MyApp
import java.util.*

class FragmentSettings : PreferenceFragment(), OnSharedPreferenceChangeListener {

    companion object {
        private const val REQUEST_CODE_OPEN_DOCUMENT_TREE = 12345 // Choose any unique request code
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        addPreferencesFromResource(R.xml.settings)
        preferenceScreen.sharedPreferences.registerOnSharedPreferenceChangeListener(this)

        updateGammaState()

        findPreference("pref_controls").setOnPreferenceClickListener {
            val intent = Intent(activity, ConfigureControls::class.java)
            this.startActivity(intent)
            true
        }

        findPreference("pref_game_settings").setOnPreferenceClickListener {
            val intent = Intent(activity, SettingsActivity::class.java)
            this.startActivity(intent)
            true
        }

        findPreference("pref_mods").setOnPreferenceClickListener {
            // Just prevent crash here if data files are not selected
            val sharedPref = preferenceScreen.sharedPreferences
            val inst = GameInstaller(sharedPref.getString("game_files", "")!!)
            if (!inst.check()) {
                AlertDialog.Builder(getActivity())
                    .setTitle(R.string.no_data_files_title)
                    .setMessage(R.string.no_data_files_message)
                    .setPositiveButton(android.R.string.ok) { _: DialogInterface, _: Int -> }
                    .show()

                false
            }
            else
            {
                val intent = Intent(activity, ModsActivity::class.java)
                this.startActivity(intent)
                true
            }
        }

        0


I changed the first part to

findPreference("game_files").setOnPreferenceClickListener {
            // Use ACTION_OPEN_DOCUMENT_TREE intent to allow the user to choose a directory
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            startActivityForResult(intent, REQUEST_CODE_OPEN_DOCUMENT_TREE)
            true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_CODE_OPEN_DOCUMENT_TREE && resultCode == Activity.RESULT_OK) {
        data?.data?.also { uri ->

            val selectedDirectory = DocumentFile.fromTreeUri(activity, uri) ?: return
            val iniFile = selectedDirectory.findFile("Morrowind.ini")
            val dataFilesFolder = selectedDirectory.findFile("Data Files")
            val sharedPref = preferenceScreen.sharedPreferences


            if (iniFile != null && dataFilesFolder != null && dataFilesFolder.isDirectory) {
                val gameFilesPreference = findPreference("game_files")
                val path = uri.toString() // Convert Uri to String path
                gameFilesPreference?.summary = path
                with(sharedPref.edit()) {
                    var gameFiles = path
                    putString("game_files", gameFiles)
                    apply()
                }
            } else {
                showError(R.string.data_error_title, R.string.data_error_message)
            }
        }
    }
}


    /**
     * Checks the specified path for a valid morrowind installation, generates config files
     * and saves the path to shared prefs if it's valid.
     * If it isn't, an error is displayed to the user.
     */
    private fun setupData(path: String) {
        val sharedPref = preferenceScreen.sharedPreferences

        // reset the setting so that it's erased on error instead of keeping
        // possibly stale value
        var gameFiles = ""

        val inst = GameInstaller(path)
        if (inst.check()) {
            val iniFile = File(path, "Morrowind.ini")
            val dataFilesFolder = File(path, "Data Files")

            if (iniFile.exists() && dataFilesFolder.exists() && dataFilesFolder.isDirectory) {
                inst.setNomedia()
                if (!inst.convertIni(sharedPref.getString("pref_encoding", GameInstaller.DEFAULT_CHARSET_PREF)!!)) {
                    showError(R.string.data_error_title, R.string.ini_error_message)
                } else {
                    gameFiles = path
                }
            } else {
                // If either Morrowind.ini or Data Files folder is missing
                showError(R.string.data_error_title, R.string.data_error_message)
            }
        } else {
            showError(R.string.data_error_title, R.string.data_error_message,
                "https://omw.xyz.is/game.html")
        }

        with(sharedPref.edit()) {
            putString("game_files", gameFiles)
            apply()
        }
    }


    /**
     * Shows an alert dialog displaying a specific error
     * @param title Title string resource
     * @param message Message string resource
     */
    private fun showError(title: Int, message: Int, url: String? = null) {
        val dialog = AlertDialog.Builder(activity)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok) { _: DialogInterface, _: Int -> }

        if (url != null) {
            dialog.setNeutralButton(R.string.dialog_howto) { _, _ ->
                (activity as MainActivity).openUrl(url)
            }
        }

        dialog.show()
    }

    override fun onResume() {
        super.onResume()
        for (i in 0 until preferenceScreen.preferenceCount) {
            val preference = preferenceScreen.getPreference(i)
            if (preference is PreferenceGroup) {
                for (j in 0 until preference.preferenceCount) {
                    val singlePref = preference.getPreference(j)
                    updatePreference(singlePref, singlePref.key)
                }
            } else {
                updatePreference(preference, preference.key)
            }
        }
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences, key: String) {
        updatePreference(findPreference(key), key)
        updateGammaState()
    }

    private fun updatePreference(preference: Preference?, key: String) {
        if (preference == null)
            return
        if (preference is EditTextPreference) {
            if (key == "pref_uiScaling" && (preference.text == null || preference.text.isEmpty()))
                // Show "Auto (1.23)"
                preference.summary = MyApp.app.getString(R.string.uiScaling_auto)
                    .format(Locale.ROOT, MyApp.app.defaultScaling)
            else
                preference.summary = preference.text
        }
        // Show selected value as a summary for game_files
        if (key == "game_files") {
            preference.summary = preference.sharedPreferences.getString("game_files", "")
        }
    }

    /**
     * @brief Disable gamma preference if GLES1 is selected
     */
    private fun updateGammaState() {
        val sharedPref = preferenceScreen.sharedPreferences
        findPreference("pref_gamma").isEnabled =
                sharedPref.getString("pref_graphicsLibrary_v2", "") != "gles1"
/*
	var isnohighpenabled = false;
        if(sharedPref.getString("pref_shadersDir_v2", "") == "modified")
		isnohighpenabled = true
        findPreference("pref_nohighp").isEnabled = isnohighpenabled

	var isAdditionalAnimSourcesEnabled = false;
        if(sharedPref.getBoolean("gs_use_additional_animation_sources", false) == true) isAdditionalAnimSourcesEnabled = true
        findPreference("gs_weapon_sheating").isEnabled = isAdditionalAnimSourcesEnabled
        findPreference("gs_shield_sheating").isEnabled = isAdditionalAnimSourcesEnabled
*/
    }

}
