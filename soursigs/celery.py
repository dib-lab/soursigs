from celery import Celery


app = Celery('soursigs',
    broker='sqs://',
    include=['soursigs.tasks'])
app.config_from_object('soursigs.celeryconfig')


if __name__ == "__main__":
    app.start()
