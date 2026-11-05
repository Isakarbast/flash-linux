/* Slides shown while Flash Linux installs. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 8000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 22
            text: "Flash Linux is being installed from the packages on this USB stick. Nothing is downloaded."
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 22
            text: "Every package is managed by fpm. Afterwards, \"fpm install <name>\" adds software and \"fpm upgrade\" updates it."
        }
    }

    function onActivate() { }
    function onLeave() { }
}
