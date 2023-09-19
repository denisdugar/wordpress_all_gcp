import functions_framework
import requests
from google.cloud import datastore
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail
import os


@functions_framework.http
def checkhttp(request):
    datastore_steps = get_variable("var", "steps")
    steps = datastore_steps["value"]
    datastore_enpoints = get_variable("var", "endpoints")
    endpoints = datastore_enpoints["value"]
    for index,e in enumerate(endpoints):
        try:
            response = requests.get(e)
            health = 'healthy' if 200 <= response.status_code < 400 else 'unhealthy'
        except:
            health = 'unhealthy'
        if health == 'healthy':
            steps[index] = 0
            store_variable("var", "steps", "value", steps)
        if health == 'unhealthy':
            steps[index] = steps[index] + 1
            if steps[index]==3:
                send_email(f"Host {e} is unhealthy")
                steps[index] = 0
                store_variable("var", "steps", "value", steps)
            else:
                store_variable("var", "steps", "value", steps)
    return "done"
def send_email(text):
    message = Mail(
        from_email='denisdugar@gmail.com',
        to_emails='denisdugar@gmail.com',
        subject='Cloud Function report',
        plain_text_content=text)
    try:
        sg = SendGridAPIClient(os.environ.get('SENDGRID_API_KEY'))
        sg.send(message)
    except Exception as e:
        print("Error: ", e)
def store_variable(kind_name, key_name, variable_name, value):
    client = datastore.Client()
    entity = datastore.Entity(key=client.key(kind_name, key_name))
    entity.update({
        variable_name : value
    })
    client.put(entity)
def get_variable(kind_name, key_name):
    client = datastore.Client()
    key = client.key(kind_name, key_name)
    entity = client.get(key)
    return dict(entity) if entity else None